--!strict

local HttpService = game:GetService("HttpService")

local Response = {}

function Response.ok<T>(data: T?, requestId: string?): any
	return {
		Success = true,
		Code = "OK",
		Message = "",
		Data = data,
		RequestId = requestId or HttpService:GenerateGUID(false),
	}
end

function Response.error(code: string, message: string, requestId: string?): any
	return {
		Success = false,
		Code = code,
		Message = message,
		Data = nil,
		RequestId = requestId or HttpService:GenerateGUID(false),
	}
end

return table.freeze(Response)
