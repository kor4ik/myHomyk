"""Fake AC with fan, swing and HVAC modes, for dashboard tests only."""
from homeassistant.components.climate import ClimateEntity, ClimateEntityFeature, HVACMode
from homeassistant.const import UnitOfTemperature


async def async_setup_platform(hass, config, async_add_entities, discovery_info=None):
    async_add_entities([StandinClimate(config["name"])])


class StandinClimate(ClimateEntity):
    _attr_temperature_unit = UnitOfTemperature.CELSIUS
    _attr_hvac_modes = [HVACMode.OFF, HVACMode.COOL, HVACMode.HEAT, HVACMode.AUTO]
    _attr_fan_modes = ["auto", "low", "medium", "high"]
    _attr_swing_modes = ["off", "vertical"]
    _attr_target_temperature_step = 1
    _attr_min_temp = 16
    _attr_max_temp = 30
    _attr_supported_features = (
        ClimateEntityFeature.TARGET_TEMPERATURE
        | ClimateEntityFeature.FAN_MODE
        | ClimateEntityFeature.SWING_MODE
        | ClimateEntityFeature.TURN_ON
        | ClimateEntityFeature.TURN_OFF
    )

    def __init__(self, name):
        self._attr_name = name
        self._attr_unique_id = name
        self._attr_hvac_mode = HVACMode.OFF
        self._attr_fan_mode = "auto"
        self._attr_swing_mode = "off"
        self._attr_current_temperature = 22
        self._attr_target_temperature = 24

    async def async_set_hvac_mode(self, hvac_mode):
        self._attr_hvac_mode = hvac_mode
        self.async_write_ha_state()

    async def async_set_fan_mode(self, fan_mode):
        self._attr_fan_mode = fan_mode
        self.async_write_ha_state()

    async def async_set_swing_mode(self, swing_mode):
        self._attr_swing_mode = swing_mode
        self.async_write_ha_state()

    async def async_set_temperature(self, **kwargs):
        self._attr_target_temperature = kwargs.get("temperature", self._attr_target_temperature)
        self.async_write_ha_state()
