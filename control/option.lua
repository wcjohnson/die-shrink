--------------------------------------------------------------------------------
-- Configurable options
--------------------------------------------------------------------------------

---@class DieShrink.InputOptionDefinition
---@field type "input"
---@field min? int Minimum value the user can enter for the option.
---@field max? int Maximum value the user can enter for the option.
---@field default? int Default value for the option if the user blanks the field.
---@field signal? SignalID The signal that will be sent into the IC with the value of the option.

---@alias DieShrink.OptionDefinition DieShrink.InputOptionDefinition
