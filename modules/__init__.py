"""
SatComHub Modular Signal Loss Factors Package.

Each factor module accepts a session prediction JSON (conforming to the schema
in README.md) and returns a time-series JSON of the evaluated physical factor
along the satellite-to-ground-station Line-of-Sight (LOS).
"""

from .rain_attenuation import RainAttenuationModule, run_rain_density_analysis

__all__ = ["RainAttenuationModule", "run_rain_density_analysis"]

