#!/usr/bin/env python3
"""Unit tests for the SatComHub Rain Attenuation (LOS Rain Density) module."""

import datetime
import json
import os
import subprocess
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from modules.rain_attenuation import (
    GeoPoint,
    RainAttenuationModule,
    WeatherProvider,
    compute_look_angles,
    run_rain_density_analysis,
)


class TestRainAttenuationModule(unittest.TestCase):
    def setUp(self) -> None:
        self.sample_path = os.path.join(os.path.dirname(__file__), "sample_input.json")
        with open(self.sample_path, "r", encoding="utf-8") as f:
            self.sample_input = json.load(f)

    def test_output_schema_matches_readme(self) -> None:
        """Verify output JSON structure and types match README specification."""
        result = run_rain_density_analysis(self.sample_input, allow_network=False)

        self.assertEqual(result["module_name"], "Rain_Attenuation")
        self.assertEqual(result["version"], 1.0)
        self.assertEqual(result["factor_name"], "rain_density")
        self.assertEqual(result["units"], "mm/m^2")
        self.assertIn("ground_stations_session_values", result)

        stations_out = result["ground_stations_session_values"]
        self.assertEqual(len(stations_out), len(self.sample_input["ground_stations_list"]))

        for st_res in stations_out:
            self.assertIn("ground_station_name", st_res)
            self.assertIn("stationId", st_res)
            self.assertIn("samples_count", st_res)
            self.assertIn("session_values", st_res)
            self.assertEqual(st_res["samples_count"], len(st_res["session_values"]))
            self.assertEqual(len(st_res["session_values"]), 2)

            for idx, item in enumerate(st_res["session_values"]):
                self.assertEqual(
                    item["utc_time"],
                    self.sample_input["satellite_session"][idx]["utc_time"],
                )
                self.assertIsInstance(item["value"], (int, float))
                self.assertGreaterEqual(item["value"], 0.0)

    def test_elevation_dependence_of_los_rain_density(self) -> None:
        """
        Verify physical behavior: a satellite at low elevation has a longer
        slant path through the rain layer than a satellite directly at zenith.
        """
        provider = WeatherProvider(allow_network=False)
        module = RainAttenuationModule(weather_provider=provider)
        station = GeoPoint(latitude_deg=52.402, longitude_deg=16.951, altitude_km=0.15)
        dt = datetime.datetime(2026, 11, 4, 11, 45, 20, tzinfo=datetime.timezone.utc)

        # Satellite directly overhead (Zenith, elevation ~90 deg)
        sat_zenith = GeoPoint(latitude_deg=52.402, longitude_deg=16.951, altitude_km=800.0)
        look_zenith = compute_look_angles(station, sat_zenith)
        self.assertGreater(look_zenith.elevation_deg, 88.0)

        # Satellite at moderate-low elevation (~18 deg)
        sat_low = GeoPoint(latitude_deg=65.0, longitude_deg=16.951, altitude_km=800.0)
        look_low = compute_look_angles(station, sat_low)
        self.assertLess(look_low.elevation_deg, 30.0)
        self.assertGreater(look_low.elevation_deg, 5.0)

        density_zenith = module.compute_los_rain_density_for_station(station, sat_zenith, dt)
        density_low = module.compute_los_rain_density_for_station(station, sat_low, dt)

        self.assertGreater(density_low, density_zenith)

    def test_per_station_visibility_and_samples_count(self) -> None:
        """
        Verify that when multiple stations have different visibility windows during a pass,
        each station gets its own separate `samples_count` and LOS `session_values`.
        """
        input_payload = {
            "satellite_session": [
                {"utc_time": "04-11-2026 11:45:20", "longitude": 21.0122, "latitiude": 52.2297, "altitude": 500.0},
                {"utc_time": "04-11-2026 11:45:21", "longitude": 21.0122, "latitiude": 50.0647, "altitude": 500.0},
                {"utc_time": "04-11-2026 11:45:22", "longitude": 31.2357, "latitiude": 30.0444, "altitude": 500.0},
            ],
            "ground_stations_list": [
                {
                    "name": "Warsaw Primary Hub",
                    "stationId": "GS-01",
                    "min_elevation_deg": 20.0,
                    "coordinates": {"latitude": 52.2297, "longitude": 21.0122, "altitude_m": 220},
                },
                {
                    "name": "Cairo South Station",
                    "stationId": "GS-02",
                    "min_elevation_deg": 20.0,
                    "coordinates": {"latitude": 30.0444, "longitude": 31.2357, "altitude_m": 100},
                },
            ],
        }
        res = run_rain_density_analysis(input_payload, allow_network=False)
        stations_out = res["ground_stations_session_values"]
        self.assertEqual(len(stations_out), 2)
        # Warsaw sees the first 2 samples at high elevation, not the 3rd at 30 deg N
        self.assertEqual(stations_out[0]["ground_station_name"], "Warsaw Primary Hub")
        self.assertEqual(stations_out[0]["samples_count"], 2)
        # Cairo only sees the 3rd sample at 30 deg N
        self.assertEqual(stations_out[1]["ground_station_name"], "Cairo South Station")
        self.assertEqual(stations_out[1]["samples_count"], 1)

    def test_cli_execution(self) -> None:
        """Verify CLI execution with --input flag outputs valid JSON."""
        script_path = os.path.join(os.path.dirname(__file__), "rain_attenuation.py")
        proc = subprocess.run(
            [sys.executable, script_path, "--input", self.sample_path, "--offline"],
            capture_output=True,
            text=True,
            check=True,
        )
        output = json.loads(proc.stdout)
        self.assertEqual(output["module_name"], "Rain_Attenuation")
        self.assertEqual(output["factor_name"], "rain_density")
        self.assertEqual(output["units"], "mm/m^2")
        self.assertIn("ground_stations_session_values", output)
        self.assertEqual(len(output["ground_stations_session_values"][0]["session_values"]), 2)


if __name__ == "__main__":
    unittest.main()
