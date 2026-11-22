"""Fake weather entity with a daily forecast, for dashboard tests only."""
from datetime import timedelta

from homeassistant.components.weather import Forecast, WeatherEntity, WeatherEntityFeature
from homeassistant.const import UnitOfTemperature
from homeassistant.util import dt as dt_util


async def async_setup_platform(hass, config, async_add_entities, discovery_info=None):
    async_add_entities([StandinWeather(config["name"])])


class StandinWeather(WeatherEntity):
    _attr_native_temperature_unit = UnitOfTemperature.CELSIUS
    _attr_supported_features = WeatherEntityFeature.FORECAST_DAILY
    _attr_condition = "sunny"
    _attr_native_temperature = 20
    _attr_humidity = 50

    def __init__(self, name):
        self._attr_name = name
        self._attr_unique_id = name

    async def async_forecast_daily(self):
        now = dt_util.now()
        return [
            Forecast(
                datetime=(now + timedelta(days=i)).isoformat(),
                native_temperature=22 + i,
                native_templow=14 + i,
                condition="sunny",
            )
            for i in range(1, 5)
        ]
