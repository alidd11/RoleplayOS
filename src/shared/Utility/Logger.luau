--!strict

local Logger = {}
Logger.__index = Logger

function Logger.new(scope: string)
	return setmetatable({ Scope = scope }, Logger)
end

function Logger:_write(level: string, message: string, metadata: any?)
	local suffix = metadata and " " .. game:GetService("HttpService"):JSONEncode(metadata) or ""
	local output = string.format("[RoleplayOS][%s][%s] %s%s", level, self.Scope, message, suffix)
	if level == "ERROR" or level == "SECURITY" or level == "WARNING" then
		warn(output)
	else
		print(output)
	end
end

function Logger:Debug(message: string, metadata: any?)
	self:_write("DEBUG", message, metadata)
end
function Logger:Info(message: string, metadata: any?)
	self:_write("INFO", message, metadata)
end
function Logger:Warning(message: string, metadata: any?)
	self:_write("WARNING", message, metadata)
end
function Logger:Error(message: string, metadata: any?)
	self:_write("ERROR", message, metadata)
end
function Logger:Security(message: string, metadata: any?)
	self:_write("SECURITY", message, metadata)
end
function Logger:Audit(message: string, metadata: any?)
	self:_write("AUDIT", message, metadata)
end

return Logger
