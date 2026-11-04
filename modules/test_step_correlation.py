#!/usr/bin/env python3
"""
Unit tests for `modules/step_correlation.py`.
"""

import os
import tempfile
import unittest

from modules.step_correlation import (
    create_default_attenuation_excel,
    evaluate_step_attenuation,
    parse_excel_factor_tables,
    run_step_correlation,
)


class TestStepCorrelationModule(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.excel_path = os.path.join(self.temp_dir.name, "attenuation_table.xlsx")
        create_default_attenuation_excel(self.excel_path)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_step_function_evaluation(self) -> None:
        """
        Verify step function rule:
        For table [(5.0, 1.0), (20.0, 4.0)]:
        - values < 5.0 -> 0.0 dB
        - value == 5.0 -> 1.0 dB
        - 5.0 < value < 20.0 -> 1.0 dB (previous attenuation from 5 mm/m^2)
        - value >= 20.0 -> 4.0 dB
        """
        thresholds = [(5.0, 1.0), (20.0, 4.0)]
        self.assertEqual(evaluate_step_attenuation(0.0, thresholds), 0.0)
        self.assertEqual(evaluate_step_attenuation(4.99, thresholds), 0.0)
        self.assertEqual(evaluate_step_attenuation(5.0, thresholds), 1.0)
        self.assertEqual(evaluate_step_attenuation(12.5, thresholds), 1.0)
        self.assertEqual(evaluate_step_attenuation(19.99, thresholds), 1.0)
        self.assertEqual(evaluate_step_attenuation(20.0, thresholds), 4.0)
        self.assertEqual(evaluate_step_attenuation(35.0, thresholds), 4.0)

    def test_identical_factor_names_success(self) -> None:
        """
        When factor names in JSON and Excel table are identical ('rain_density'),
        status is 0 and message is 'Finished'.
        """
        input_json = {
            "ground_station_name": "Piotrowo C-band",
            "samples_count": 6,
            "factors_list": [
                {
                    "factor_name": "rain_density",
                    "factor_units": "mm/m^2",
                    "values": [0, 3, 5, 14, 20, 25],
                }
            ],
        }
        res = run_step_correlation(input_json, self.excel_path)
        self.assertEqual(res["status"], 0)
        self.assertEqual(res["message"], "Finished")
        self.assertEqual(res["sample_count"], 6)
        self.assertEqual(res["total_attenuation_db_list"], [0.0, 0.0, 1.0, 1.0, 4.0, 4.0])

    def test_non_identical_factor_names_warning(self) -> None:
        """
        When factor name casing differs ('Rain_density' vs 'rain_density'),
        status is 0 and output JSON contains a warning message.
        """
        input_json = {
            "ground_station_name": "Piotrowo C-band",
            "samples_count": 3,
            "factors_list": [
                {
                    "factor_name": "Rain_density",
                    "factor_units": "mm/m^2",
                    "values": [0, 5, 20],
                }
            ],
        }
        res = run_step_correlation(input_json, self.excel_path)
        self.assertEqual(res["status"], 0)
        self.assertIn("Warning:", res["message"])
        self.assertEqual(res["total_attenuation_db_list"], [0.0, 1.0, 4.0])

    def test_missing_factor_in_excel_returns_error(self) -> None:
        """
        When a factor in main program JSON is not in the Excel table,
        return error status and error message in output JSON.
        """
        input_json = {
            "ground_station_name": "Piotrowo C-band",
            "samples_count": 3,
            "factors_list": [
                {
                    "factor_name": "rain_density",
                    "factor_units": "mm/m^2",
                    "values": [0, 5, 20],
                },
                {
                    "factor_name": "Ground_Station_Wind_Speed",
                    "factor_units": "km/h",
                    "values": [10, 15, 20],
                },
            ],
        }
        res = run_step_correlation(input_json, self.excel_path)
        self.assertEqual(res["status"], 1)
        self.assertIn("Error:", res["message"])
        self.assertIn("Ground_Station_Wind_Speed", res["message"])
        self.assertEqual(res["total_attenuation_db_list"], [])


if __name__ == "__main__":
    unittest.main()

