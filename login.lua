local cjson = require "cjson";
local redis = require "resty.redis";

REDIS_SERVER_IP = "127.0.0.1"
REDIS_SERVER_PORT = 6379
REDIS_TIMEOUT = 1000

KEY_ALL_MEMBER_LIST = 'all_member_list'
KEY_LOGIN_MEMBER_LIST = 'login_member_list'
KEY_DRAW_MEMBER_LIST = 'draw_member_list'

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

function parse_postargs()
	ngx.req.read_body()
	args = ngx.req.get_post_args()
	phone = args['phone']
	name = args['name']

	if not args then
		ngx.say("failed get args:")
	end
end

function add_new_user()
	local res, err = red:sadd(KEY_ALL_MEMBER_LIST, phone)
	if not res then
		ngx.say("failed to sadd all member list")
	end

	local res_name, err = red:hset(phone, 'name', name)
	local res_lev, err = red:hset(phone, 'level', 4)
	if not res_name or not res_lev then
		ngx.say("failed to set new member")
	end

	local successed_str = string.format("name: %s, phone: %s", phone, name)
	ngx.say(successed_str)	
end

function login_user()
	local res, err = red:sismember(KEY_ALL_MEMBER_LIST, phone)
	if not res then
		ngx.say("failed to sismember")
	end
	
	if (res == 0) then
		ngx.say("this phone not exist")
		ngx.exit(ngx.HTTP_OK)
	end

	local res, err = red:sadd(KEY_LOGIN_MEMBER_LIST, phone)
	if not res then
		ngx.say("failed to sadd")
	end
	ngx.say("login successed!")
end

function draw()
	local count,err = red:incr("activity_count")
	if not count then
		ngx.say("failed to sadd")
		ngx.exit(ngx.HTTP_OK)
	end


    while(1) do 
	    local win_phone,err = red:srandmember(KEY_LOGIN_MEMBER_LIST)
	    if not win_phone then
	    	ngx.say("failed to srandmember")
	    end

        local remain, err = red:scard(KEY_LOGIN_MEMBER_LIST)
	    if not remain then
	    	ngx.say("failed to scard")
	    end

        if(remain == 0) then
            break
        end

	    local has_draw, err = red:sismember(KEY_DRAW_MEMBER_LIST, phone)
	    if not has_draw then
	    	ngx.say("failed to sismember")
	    end

	    if (has_draw == 0) then
	        local level = 4
	        if(count <= 4) then
 	        	level = 3					
	        elseif(count > 4) and (count <= 6) then
	        	level = 2 
	        elseif(count == 7) then
	        	level = 1
	        end

	        local res, err = red:sadd(KEY_DRAW_MEMBER_LIST, win_phone)
	        if not res then
	        	ngx.say("failed to sadd")
	        end

	        local res_lev, err = red:hset(phone, 'level', level)
	        if not res_lev then
	        	ngx.say("failed to set new member")
	        end

	        res_str = string.format('level: %d,phone: %s', level, win_phone)
            break
	    end

	    local res_rem, err = red:srem(KEY_LOGIN_MEMBER_LIST, phone)
	    if not res_lev then
	    	ngx.say("failed to set new member")
	    end
	    
    end
	
	ngx.say(res_str)
	ngx.exit(ngx.HTTP_OK)
end

function main()
	init_redis()	
	parse_postargs()

	local op_action = {
		["add"] = function() return add_new_user() end,
		["login"] = function() return login_user() end, 
		["draw"] = function() return draw() end, 
	}

	op_name = args["opname"]
	if not op_action[op_name] then 
		ngx.say("get op_name error")		
	end

	op_action[op_name]()
end


main()
