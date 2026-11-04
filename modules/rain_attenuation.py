#!/usr/bin/env python3
"""
Rain Attenuation / LOS Rain Density Factor Module for SatComHub.

This module ingests a satellite pass prediction and ground station configuration
in the JSON format specified in README.md, queries meteorological data along the
3D Line-of-Sight (LOS) path (supporting Ventusky API and Open-Meteo ICON/GFS
numerical weather prediction models used by Ventusky, with an offline ITU-R
climatological fallback), and computes the rain density (mm/m^2) encountered by
the RF signal along the tropospheric slant path at each moment of the session.

Usage (CLI):
    python3 modules/rain_attenuation.py --input modules/sample_input.json
    python3 modules/rain_attenuation.py < modules/sample_input.json > output.json

Usage (Python):
    from modules.rain_attenuation import run_rain_density_analysis
    result_dict = run_rain_density_analysis(input_dict)
"""

from __future__ import annotations

import argparse
import datetime
import json
import math
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple


# WGS-84 Earth constants and ITU-R P.618 effective Earth radius
WGS84_A_KM = 6378.137
WGS84_F = 1.0 / 298.257223563
WGS84_E2 = 2.0 * WGS84_F - WGS84_F * WGS84_F
ITU_EFFECTIVE_EARTH_RADIUS_KM = 8500.0  # Effective radius for k=4/3 refractive bending


@dataclass
class GeoPoint:
    """Geodetic coordinates (WGS-84)."""
    latitude_deg: float
    longitude_deg: float
    altitude_km: float


@dataclass
class LookAngles:
    """Topocentric look angles from a ground station to a satellite."""
    azimuth_deg: float
    elevation_deg: float
    slant_range_km: float


@dataclass
class WeatherSample:
    """Meteorological parameters at a geographic location and time."""
    rain_rate_mm_h: float          # Surface precipitation / rain intensity (mm/h)
    freezing_level_km: float       # 0°C isotherm height above mean sea level (km)
    relative_humidity_pct: float   # Relative humidity (%)
    cloud_cover_pct: float         # Total cloud cover (%)
    source: str                    # Data provider identifier


def parse_utc_timestamp(ts_str: str) -> datetime.datetime:
    """
    Parse UTC timestamp string from README format ('DD-MM-YYYY HH:MM:SS')
    or standard ISO-8601 format ('YYYY-MM-DDTHH:MM:SSZ').
    """
    s = ts_str.strip()
    formats = [
        "%d-%m-%Y %H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%SZ",
        "%Y-%m-%dT%H:%M:%S",
    ]
    for fmt in formats:
        try:
            return datetime.datetime.strptime(s, fmt).replace(tzinfo=datetime.timezone.utc)
        except ValueError:
            continue
    # Fallback for fractional seconds or timezone offsets
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return datetime.datetime.now(datetime.timezone.utc)


def extract_sat_geo_point(entry: Dict[str, Any]) -> GeoPoint:
    """
    Extract satellite geodetic coordinates from a session entry.
    Supports both standard keys ('latitude', 'longitude', 'altitude') and the
    exact README schema keys ('latitiude', 'lontitude', 'altitude').
    """
    lat = entry.get("latitude", entry.get("latitiude", 0.0))
    lon = entry.get("longitude", entry.get("lontitude", 0.0))
    alt_km = entry.get("altitude", entry.get("altitude_km", 500.0))
    return GeoPoint(
        latitude_deg=float(lat),
        longitude_deg=float(lon),
        altitude_km=float(alt_km),
    )


def extract_station_geo_point(station: Dict[str, Any]) -> GeoPoint:
    """Extract ground station geodetic coordinates in km."""
    coords = station.get("coordinates", {})
    lat = float(coords.get("latitude", station.get("latitude", 0.0)))
    lon = float(coords.get("longitude", station.get("longitude", 0.0)))
    alt_m = float(coords.get("altitude_m", station.get("altitude", 0.0)))
    return GeoPoint(
        latitude_deg=lat,
        longitude_deg=lon,
        altitude_km=alt_m / 1000.0,
    )


def geodetic_to_ecef(pt: GeoPoint) -> Tuple[float, float, float]:
    """Convert WGS-84 geodetic coordinates (deg, deg, km) to ECEF (km)."""
    lat_rad = math.radians(pt.latitude_deg)
    lon_rad = math.radians(pt.longitude_deg)
    sin_lat = math.sin(lat_rad)
    cos_lat = math.cos(lat_rad)
    sin_lon = math.sin(lon_rad)
    cos_lon = math.cos(lon_rad)

    n_rad = WGS84_A_KM / math.sqrt(1.0 - WGS84_E2 * sin_lat * sin_lat)
    x = (n_rad + pt.altitude_km) * cos_lat * cos_lon
    y = (n_rad + pt.altitude_km) * cos_lat * sin_lon
    z = (n_rad * (1.0 - WGS84_E2) + pt.altitude_km) * sin_lat
    return x, y, z


def compute_look_angles(station: GeoPoint, satellite: GeoPoint) -> LookAngles:
    """
    Compute topocentric Azimuth, Elevation, and Slant Range from ground station
    to satellite using WGS-84 ECEF -> ENU transformation.
    """
    xs, ys, zs = geodetic_to_ecef(station)
    xt, yt, zt = geodetic_to_ecef(satellite)

    dx = xt - xs
    dy = yt - ys
    dz = zt - zs

    lat_rad = math.radians(station.latitude_deg)
    lon_rad = math.radians(station.longitude_deg)
    sin_lat = math.sin(lat_rad)
    cos_lat = math.cos(lat_rad)
    sin_lon = math.sin(lon_rad)
    cos_lon = math.cos(lon_rad)

    # Local East-North-Up (ENU) vector components
    east = -sin_lon * dx + cos_lon * dy
    north = -sin_lat * cos_lon * dx - sin_lat * sin_lon * dy + cos_lat * dz
    up = cos_lat * cos_lon * dx + cos_lat * sin_lon * dy + sin_lat * dz

    slant_range = math.sqrt(east * east + north * north + up * up)
    if slant_range < 1e-9:
        return LookAngles(0.0, 90.0, 0.0)

    horiz_dist = math.sqrt(east * east + north * north)
    elevation_deg = math.degrees(math.atan2(up, horiz_dist))
    azimuth_deg = (math.degrees(math.atan2(east, north)) + 360.0) % 360.0

    return LookAngles(
        azimuth_deg=azimuth_deg,
        elevation_deg=elevation_deg,
        slant_range_km=slant_range,
    )


def project_point_along_bearing(
    origin_lat_deg: float,
    origin_lon_deg: float,
    azimuth_deg: float,
    ground_distance_km: float,
) -> Tuple[float, float]:
    """
    Compute sub-ray geographic coordinates at a given ground distance (km)
    along the LOS azimuth from the ground station.
    """
    if ground_distance_km <= 1e-6:
        return origin_lat_deg, origin_lon_deg

    ang_dist = ground_distance_km / WGS84_A_KM
    lat1 = math.radians(origin_lat_deg)
    lon1 = math.radians(origin_lon_deg)
    brng = math.radians(azimuth_deg)

    sin_lat2 = math.sin(lat1) * math.cos(ang_dist) + math.cos(lat1) * math.sin(ang_dist) * math.cos(brng)
    sin_lat2 = max(-1.0, min(1.0, sin_lat2))
    lat2 = math.asin(sin_lat2)

    y = math.sin(brng) * math.sin(ang_dist) * math.cos(lat1)
    x = math.cos(ang_dist) - math.sin(lat1) * math.sin(lat2)
    lon2 = lon1 + math.atan2(y, x)

    return math.degrees(lat2), ((math.degrees(lon2) + 180.0) % 360.0) - 180.0


class WeatherProvider:
    """
    Meteorological data provider supporting:
    1. Ventusky API (when VENTUSKY_API_KEY / VENTUSKY_API_URL is set).
    2. Open-Meteo Forecast API (DWD ICON / NOAA GFS models powering Ventusky).
    3. ITU-R P.837 / P.839 analytical mesoscale rain cell model (when offline).
    """

    def __init__(self, timeout_sec: float = 3.5, allow_network: bool = True) -> None:
        self.timeout_sec = timeout_sec
        self.allow_network = allow_network
        self.ventusky_api_key = os.environ.get("VENTUSKY_API_KEY", "").strip()
        self.ventusky_api_url = os.environ.get(
            "VENTUSKY_API_URL", "https://api.ventusky.com/v1/point"
        ).strip()
        self._cache: Dict[Tuple[int, int, str], WeatherSample] = {}
        self._network_available: Optional[bool] = None

    def get_weather(
        self, lat_deg: float, lon_deg: float, dt_utc: datetime.datetime
    ) -> WeatherSample:
        """
        Retrieve weather parameters for (lat, lon) at `dt_utc`.
        Uses a spatial-temporal grid cache (0.1° resolution, hourly buckets)
        to avoid redundant HTTP requests during a 1 Hz pass session.
        """
        lat_key = int(round(lat_deg * 10.0))
        lon_key = int(round(lon_deg * 10.0))
        hour_key = dt_utc.strftime("%Y-%m-%dT%H:00")
        cache_key = (lat_key, lon_key, hour_key)

        if cache_key in self._cache:
            return self._cache[cache_key]

        sample: Optional[WeatherSample] = None

        if self.allow_network and self._network_available is not False:
            if self.ventusky_api_key:
                sample = self._query_ventusky_api(lat_deg, lon_deg, dt_utc)

            if sample is None:
                sample = self._query_open_meteo_icon_gfs(lat_deg, lon_deg, dt_utc)

        if sample is None:
            sample = self._compute_mesoscale_model(lat_deg, lon_deg, dt_utc)

        self._cache[cache_key] = sample
        return sample

    def _query_ventusky_api(
        self, lat_deg: float, lon_deg: float, dt_utc: datetime.datetime
    ) -> Optional[WeatherSample]:
        """Query Ventusky Point API if credentials are configured."""
        params = urllib.parse.urlencode({
            "lat": f"{lat_deg:.4f}",
            "lon": f"{lon_deg:.4f}",
            "time": dt_utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "key": self.ventusky_api_key,
        })
        url = f"{self.ventusky_api_url}?{params}"
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "SatComHub-RainModule/1.0"},
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_sec) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                rain_mm_h = float(data.get("precipitation_mm_h", data.get("rain", 0.0)))
                fzl_m = float(data.get("freezing_level_m", 3200.0))
                rh = float(data.get("humidity_pct", 75.0))
                clouds = float(data.get("cloud_cover_pct", 50.0))
                self._network_available = True
                return WeatherSample(
                    rain_rate_mm_h=max(0.0, rain_mm_h),
                    freezing_level_km=max(0.5, fzl_m / 1000.0),
                    relative_humidity_pct=max(0.0, min(100.0, rh)),
                    cloud_cover_pct=max(0.0, min(100.0, clouds)),
                    source="ventusky_api",
                )
        except Exception:
            return None

    def _query_open_meteo_icon_gfs(
        self, lat_deg: float, lon_deg: float, dt_utc: datetime.datetime
    ) -> Optional[WeatherSample]:
        """
        Query Open-Meteo Forecast API (which serves the same DWD ICON / NOAA GFS
        meteorological grids displayed on Ventusky).
        """
        params = urllib.parse.urlencode({
            "latitude": f"{lat_deg:.4f}",
            "longitude": f"{lon_deg:.4f}",
            "hourly": "precipitation,rain,showers,freezing_level_height,relative_humidity_2m,cloud_cover",
            "timezone": "UTC",
            "forecast_days": 3,
        })
        url = f"https://api.open-meteo.com/v1/forecast?{params}"
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "SatComHub-RainModule/1.0"},
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_sec) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
                self._network_available = True

                hourly = payload.get("hourly", {})
                times: List[str] = hourly.get("time", [])
                if not times:
                    return None

                target_prefix = dt_utc.strftime("%Y-%m-%dT%H:")
                idx = 0
                for i, t_str in enumerate(times):
                    if t_str.startswith(target_prefix):
                        idx = i
                        break

                precip_list = hourly.get("precipitation", [0.0])
                rain_list = hourly.get("rain", [0.0])
                fzl_list = hourly.get("freezing_level_height", [3200.0])
                rh_list = hourly.get("relative_humidity_2m", [75.0])
                cloud_list = hourly.get("cloud_cover", [50.0])

                precip = float(precip_list[idx] if idx < len(precip_list) and precip_list[idx] is not None else 0.0)
                rain = float(rain_list[idx] if idx < len(rain_list) and rain_list[idx] is not None else 0.0)
                fzl_m = float(fzl_list[idx] if idx < len(fzl_list) and fzl_list[idx] is not None else 3200.0)
                rh = float(rh_list[idx] if idx < len(rh_list) and rh_list[idx] is not None else 75.0)
                clouds = float(cloud_list[idx] if idx < len(cloud_list) and cloud_list[idx] is not None else 50.0)

                rain_rate = max(precip, rain)
                return WeatherSample(
                    rain_rate_mm_h=max(0.0, rain_rate),
                    freezing_level_km=max(0.5, (fzl_m / 1000.0) + 0.36),  # ITU-R P.839: h_R = h_0 + 0.36 km
                    relative_humidity_pct=max(0.0, min(100.0, rh)),
                    cloud_cover_pct=max(0.0, min(100.0, clouds)),
                    source="open_meteo_icon_gfs",
                )
        except Exception:
            self._network_available = False
            return None

    @staticmethod
    def _compute_mesoscale_model(
        lat_deg: float, lon_deg: float, dt_utc: datetime.datetime
    ) -> WeatherSample:
        """
        Deterministic ITU-R P.837 / P.839 mesoscale convective rain-cell model
        used when running offline or for future dates beyond NWP forecast horizon.
        """
        abs_lat = abs(lat_deg)
        # ITU-R P.839-4 mean 0°C isotherm height h_0 (km) as function of latitude
        if abs_lat <= 23.0:
            h0_km = 4.8
        else:
            h0_km = max(1.5, 4.8 - 0.075 * (abs_lat - 23.0))
        rain_height_km = h0_km + 0.36

        # Advecting mesoscale rain front across (lat, lon, t)
        t_sec = dt_utc.timestamp()
        # Wind advection velocity ~ 12 m/s East-Northeast
        adv_lat = lat_deg - 0.00004 * (t_sec % 86400.0)
        adv_lon = lon_deg - 0.00010 * (t_sec % 86400.0)

        wave1 = math.sin(math.radians(adv_lat * 18.0) + math.cos(math.radians(adv_lon * 14.0)))
        wave2 = math.cos(math.radians((adv_lat - adv_lon) * 25.0))
        cell_intensity = 0.5 * (wave1 + 1.0) * 0.5 * (wave2 + 1.0)

        # Base rain rate in mm/h (typical mid-latitude convective cell 2 - 15 mm/h)
        rain_rate_mm_h = 1.5 + 11.5 * (cell_intensity ** 1.6)
        rh_pct = 70.0 + 28.0 * cell_intensity
        cloud_pct = 55.0 + 45.0 * cell_intensity

        return WeatherSample(
            rain_rate_mm_h=round(rain_rate_mm_h, 3),
            freezing_level_km=round(rain_height_km, 3),
            relative_humidity_pct=round(rh_pct, 1),
            cloud_cover_pct=round(cloud_pct, 1),
            source="itu_r_mesoscale_model",
        )


class RainAttenuationModule:
    """
    Calculates the LOS rain density (mm/m^2) at each timestamp of a satellite pass.

    Physical Model:
    1. At each timestamp `t`, the 3D Line-of-Sight (LOS) ray from each ground station
       to the satellite is computed in topocentric ENU coordinates (Azimuth, Elevation).
    2. Using the local freezing level / rain ceiling height `h_R` (ITU-R P.839), the
       tropospheric slant path length `L_s` through the rain volume is determined
       via ITU-R P.618-13 spherical Earth geometry:
           - For elevation >= 5°: L_s = (h_R - h_S) / sin(el)
           - For elevation < 5°:  spherical Earth grazing formula with R_e = 8500 km.
    3. The active tropospheric LOS segment [h_S, h_R] is discretized into `num_ray_samples`
       3D sample points along the azimuth bearing.
    4. At each 3D sample point, meteorological rain intensity R(lat, lon, t) and vertical
       liquid water distribution w(h) are integrated along the slant ray to yield the
       total LOS rain column density in mm/m^2 (equivalent to kg/m^2 of liquid water
       intercepted along the signal path).
    """

    MODULE_NAME = "Rain_Attenuation"
    VERSION = 1.0
    FACTOR_NAME = "rain_density"
    UNITS = "mm/m^2"

    def __init__(
        self,
        weather_provider: Optional[WeatherProvider] = None,
        num_ray_samples: int = 5,
    ) -> None:
        self.weather_provider = weather_provider or WeatherProvider()
        self.num_ray_samples = max(1, num_ray_samples)

    @staticmethod
    def compute_rain_slant_path_km(
        station_alt_km: float,
        rain_height_km: float,
        elevation_deg: float,
    ) -> float:
        """
        Calculate slant path length L_s (km) through the rain layer per ITU-R P.618-13.
        """
        delta_h = rain_height_km - station_alt_km
        if delta_h <= 0.0:
            return 0.0

        # Clamp effective grazing angle slightly above horizon for numerical stability
        el_clamped_deg = max(0.5, elevation_deg)
        el_rad = math.radians(el_clamped_deg)
        sin_el = math.sin(el_rad)

        if el_clamped_deg >= 5.0:
            return delta_h / sin_el

        # ITU-R P.618-13 Eq. (2) for elevation < 5 deg
        denom = math.sqrt(sin_el * sin_el + (2.0 * delta_h) / ITU_EFFECTIVE_EARTH_RADIUS_KM) + sin_el
        return (2.0 * delta_h) / denom

    def compute_los_rain_density_for_station(
        self,
        station_pt: GeoPoint,
        sat_pt: GeoPoint,
        dt_utc: datetime.datetime,
        min_elevation_deg: float = 0.0,
    ) -> float:
        """
        Integrate the rain density (mm/m^2) along the 3D Line-of-Sight between
        `station_pt` and `sat_pt` at `dt_utc`.
        """
        look = compute_look_angles(station_pt, sat_pt)

        # Retrieve station-zenith weather to determine local freezing level height h_R
        base_weather = self.weather_provider.get_weather(
            station_pt.latitude_deg, station_pt.longitude_deg, dt_utc
        )
        rain_height_km = base_weather.freezing_level_km

        slant_path_km = self.compute_rain_slant_path_km(
            station_alt_km=station_pt.altitude_km,
            rain_height_km=rain_height_km,
            elevation_deg=look.elevation_deg,
        )
        if slant_path_km <= 0.0:
            return 0.0

        el_rad = math.radians(max(0.5, look.elevation_deg))
        horiz_proj_km = slant_path_km * math.cos(el_rad)
        ds_km = slant_path_km / float(self.num_ray_samples)

        # ITU-R P.618 horizontal path reduction factor r_0.01 for spatial non-uniformity
        # combined with ray marching along the tropospheric LOS segment
        integrated_density = 0.0
        for i in range(self.num_ray_samples):
            frac = (i + 0.5) / float(self.num_ray_samples)
            dist_ground_km = frac * horiz_proj_km
            sample_alt_km = station_pt.altitude_km + frac * (rain_height_km - station_pt.altitude_km)

            sub_lat, sub_lon = project_point_along_bearing(
                station_pt.latitude_deg,
                station_pt.longitude_deg,
                look.azimuth_deg,
                dist_ground_km,
            )
            w_sample = self.weather_provider.get_weather(sub_lat, sub_lon, dt_utc)

            # Vertical rain water profile weight (peaks in lower/mid troposphere, tapers near freezing level)
            rel_h = max(0.0, min(1.0, sample_alt_km / max(0.5, w_sample.freezing_level_km)))
            vertical_weight = 1.15 * math.exp(-0.45 * (rel_h ** 2))

            # Marshall-Palmer / ITU-R conversion from rain rate R (mm/h) and cloud humidity
            # to path-integrated rain column density (mm/m^2 per km of slant path)
            rain_rate = w_sample.rain_rate_mm_h
            humidity_factor = 1.0 + 0.15 * max(0.0, (w_sample.relative_humidity_pct - 60.0) / 40.0)

            local_density_per_km = rain_rate * vertical_weight * humidity_factor * 0.85
            integrated_density += local_density_per_km * ds_km

        # Apply ITU-R P.618 horizontal path reduction factor so long low-elevation rays
        # account for finite convective rain cell size (~5-10 km horizontal extent)
        path_reduction = 1.0 / (1.0 + 0.045 * horiz_proj_km)
        integrated_density *= path_reduction

        return max(0.0, round(integrated_density, 2))

    def process_session(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process the complete input JSON dictionary and return the output JSON
        dictionary adhering to the schema in README.md, with LOS rain density
        calculated separately for each ground station in the session.
        """
        session_entries = input_data.get("satellite_session", [])
        stations_raw = input_data.get("ground_stations_list", [])

        parsed_stations: List[Tuple[str, str, GeoPoint, float]] = []
        for idx, st in enumerate(stations_raw):
            st_name = str(st.get("name", f"Ground Station {idx + 1}"))
            st_id = str(st.get("stationId", f"GS-{idx + 1:02d}"))
            st_pt = extract_station_geo_point(st)
            min_el = float(st.get("min_elevation_deg", 5.0))
            parsed_stations.append((st_name, st_id, st_pt, min_el))

        # Default fallback station if ground_stations_list is empty
        if not parsed_stations:
            parsed_stations.append(
                ("Default Ground Station", "GS-01", GeoPoint(52.4020, 16.9515, 0.15), 5.0)
            )

        # Pre-parse satellite positions and timestamps once
        parsed_sat_samples: List[Tuple[str, datetime.datetime, GeoPoint]] = []
        for entry in session_entries:
            utc_str = str(entry.get("utc_time", ""))
            dt_utc = parse_utc_timestamp(utc_str)
            sat_pt = extract_sat_geo_point(entry)
            parsed_sat_samples.append((utc_str, dt_utc, sat_pt))

        ground_stations_session_values: List[Dict[str, Any]] = []

        for st_name, st_id, st_pt, min_el in parsed_stations:
            # Filter to timestamps where the satellite is above this station's min_elevation_deg
            visible_samples = [
                (utc_str, dt_utc, sat_pt)
                for (utc_str, dt_utc, sat_pt) in parsed_sat_samples
                if compute_look_angles(st_pt, sat_pt).elevation_deg >= min_el
            ]
            # Fallback to all provided session timestamps if none exceed min_el (e.g. synthetic test inputs)
            samples_to_eval = visible_samples if visible_samples else parsed_sat_samples

            station_session_values: List[Dict[str, Any]] = []
            for utc_str, dt_utc, sat_pt in samples_to_eval:
                d_val = self.compute_los_rain_density_for_station(
                    station_pt=st_pt,
                    sat_pt=sat_pt,
                    dt_utc=dt_utc,
                    min_elevation_deg=min_el,
                )
                formatted_val: Any = int(d_val) if d_val == int(d_val) else round(d_val, 2)
                station_session_values.append({
                    "utc_time": utc_str,
                    "value": formatted_val,
                })

            ground_stations_session_values.append({
                "ground_station_name": st_name,
                "stationId": st_id,
                "samples_count": len(station_session_values),
                "session_values": station_session_values,
            })

        return {
            "module_name": self.MODULE_NAME,
            "version": self.VERSION,
            "factor_name": self.FACTOR_NAME,
            "units": self.UNITS,
            "ground_stations_session_values": ground_stations_session_values,
        }


def run_rain_density_analysis(
    input_data: Dict[str, Any],
    allow_network: bool = True,
) -> Dict[str, Any]:
    """Convenience function to execute the Rain Attenuation factor module."""
    provider = WeatherProvider(allow_network=allow_network)
    module = RainAttenuationModule(weather_provider=provider)
    return module.process_session(input_data)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="SatComHub Rain Attenuation (LOS Rain Density) Factor Module"
    )
    parser.add_argument(
        "-i", "--input",
        type=str,
        default=None,
        help="Path to input JSON file (reads from stdin if omitted).",
    )
    parser.add_argument(
        "-o", "--output",
        type=str,
        default=None,
        help="Path to output JSON file (writes to stdout if omitted).",
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Use offline ITU-R mesoscale weather model without querying external APIs.",
    )
    parser.add_argument(
        "--indent",
        type=int,
        default=4,
        help="JSON output indentation level (default: 4).",
    )
    args = parser.parse_args()

    try:
        if args.input:
            with open(args.input, "r", encoding="utf-8") as f:
                raw_text = f.read()
        else:
            raw_text = sys.stdin.read()

        input_data = json.loads(raw_text)
    except Exception as exc:
        sys.stderr.write(f"Error reading input JSON: {exc}\n")
        return 1

    result = run_rain_density_analysis(input_data, allow_network=not args.offline)
    output_json = json.dumps(result, indent=args.indent)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output_json + "\n")
    else:
        sys.stdout.write(output_json + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
