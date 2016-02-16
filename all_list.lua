local cjson = require "cjson";
local redis = require "resty.redis";

REDIS_SERVER_IP = "127.0.0.1"
REDIS_SERVER_PORT = 6379
REDIS_TIMEOUT = 1000

KEY_ALL_MEMBER_LIST = 'all_member_list'
KEY_LOGIN_MEMBER_LIST = 'login_member_list'

function init_redis()
	red = redis:new()
	red:set_timeout(REDIS_TIMEOUT)

	local ok, err = red:connect(REDIS_SERVER_IP, REDIS_SERVER_PORT)
	if not ok then
		ngx.say("fail to connect: ", err)
	end
end

function close_redis()
	local ok, err = red:setkeepalive(10000, 100)
end

function get_all_list()
	local list,err = red:smembers(KEY_ALL_MEMBER_LIST)
	if not list then
		ngx.say("failed to smember")
	end
	local list_len = table.getn(list)
	for i=1, list_len do
		local name = red:hget(list[i], 'name')
		local res_str = string.format('phone: %d,name: %s', list[i], name)
		ngx.say(res_str)
	end
end

function main()
	init_redis()	
	get_all_list()
end


main()
