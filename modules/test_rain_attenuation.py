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
        self.assertIn("session_values", result)
        self.assertEqual(len(result["session_values"]), 2)

        for idx, item in enumerate(result["session_values"]):
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
        self.assertEqual(len(output["session_values"]), 2)


if __name__ == "__main__":
    unittest.main()

