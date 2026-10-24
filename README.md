# Transmission parameters adaptation for Cubesat satellites

The main purpose of the software is to generate Session Plan file that will be executed on a satellite during its flyby over specified ground stations.

# Content

# 1. How to install

# 2. Next

```json
{
    "coordinates": [
        [55.7558, 37.6173, 1000],
        [55.7558, 37.6173, 1000]
    ]
}
```
```json
[
    {
        "factors": [
            {
                "name": "Air temperature",
                "unit": "celsius",
                "values": [-30, -20, -10, 0, 10, 20, 30, 40, 50]
            },
            {
                "name": "Humidity",
                "unit": "percent",
                "values": [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
            }
        ],
        "attenuation": []
    },
    {
        "factors": [
            {
                "name": "Distance",
                "unit": "km",
                "values": [200, 400, 600, 800, 1000, 1200, 1400, 1600, 1800, 2000]
            }
        ],
        "attenuation": []
    }
]
```