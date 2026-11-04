"""
SatComHub Modular Signal Loss Factors & Attenuation Correlation Package.

- Factor calculation modules (e.g., `rain_attenuation.py`) accept a session prediction
  JSON (Section 2 of README.md) and return a time-series JSON of the evaluated physical
  factor along the satellite-to-ground-station Line-of-Sight (Section 3 of README.md).
- Correlation modules (e.g., `step_correlation.py`) accept per-station factor arrays
  (Section 4 of README.md) together with an Excel (.xlsx) lookup table or model and
  return predicted total attenuation in dB for each moment of the session.
"""

from .rain_attenuation import RainAttenuationModule, run_rain_density_analysis
from .step_correlation import (
    create_default_attenuation_excel,
    evaluate_step_attenuation,
    parse_excel_factor_tables,
    run_step_correlation,
)

__all__ = [
    "RainAttenuationModule",
    "run_rain_density_analysis",
    "create_default_attenuation_excel",
    "evaluate_step_attenuation",
    "parse_excel_factor_tables",
    "run_step_correlation",
]
