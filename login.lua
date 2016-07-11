local cjson = require "cjson";
local redis = require "resty.redis";

REDIS_SERVER_IP = "127.0.0.1"
REDIS_SERVER_PORT = 6379
REDIS_TIMEOUT = 1000

KEY_ALL_MEMBER_LIST = 'all_member_list'
KEY_LOGIN_MEMBER_LIST = 'login_member_list'
KEY_DRAW_MEMBER_LIST = 'draw_member_list'

SET_VALUE = 'draw_set_value'

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
    
    op_name = args["opname"]
    if(op_name == 'set') then
        local field_name = {'field_1', 'field_2', 'field_3', 'field_4', 'field_5', 'field_6', 'field_7', 'field_8', 'field_9'}

        for i, v in pairs(field_name) do 
            if args[v] and (args[v] ~= "") then
                red:hset(SET_VALUE, v, args[v])
            end
        end
    end

	phone = args['phone']
	name = args['name']

	if not args then
		ngx.say("failed get args:")
	end
end

function add_new_user()
    local respon = {}

	local res, err = red:sadd(KEY_ALL_MEMBER_LIST, phone)
	if not res then
		ngx.say("failed to sadd all member list")
	end

	local res_name, err = red:hset(phone, 'name', name)
	if not res_name then
		ngx.say("failed to set new member")
	end

    respon['name'] = name
    respon['phone'] = phone

	ngx.say(cjson.encode(respon))	
end

function login_user()
    local respon = {}
    local code = -1 
    local detail = "ok"
    local order = 0
    
	local res, err = red:sismember(KEY_ALL_MEMBER_LIST, phone)
	if (not res) or (res == 0) then
        code = -2
        detail = "this phone is not exist"
    else
        local is_exist = red:exists(phone)
        if (is_exist ~= 0) then
            --更新登录序列
            local login_count = red:scard(KEY_LOGIN_MEMBER_LIST)
            if not login_count then
                login_count = 0
            end
            order = login_count + 1;
            red:hset(phone, order)

	        local res, err = red:sadd(KEY_LOGIN_MEMBER_LIST, phone)
	        if not res then
                code = -3
                detail = "login failed"
	        end
            
            code = 0
        else
            code = -4
        end

	end

    respon['code'] = code
    respon['detail'] = detail 
    respon['order'] = order 
	ngx.say(cjson.encode(respon))	
    ngx.exit(ngx.HTTP_OK)
end

function get_level(draw_number)
    local level = 0 

	local first_number, err = red:hget(SET_VALUE, 'field_1')
    if not first_number then
        first_number = 1
    end

	local second_number, err = red:hget(SET_VALUE, 'field_2')
    if not second_number then
        second_number = 2 
    end

	local third_number, err = red:hget(SET_VALUE, 'field_3')
    if not third_number then
        third_number = 3 
    end

    first_number = tonumber(first_number)
    second_number = tonumber(second_number)
    third_number = tonumber(third_number)

    if(draw_number < third_number) then
        level = 3
    elseif( draw_number < (third_number + second_number) ) then
        level = 2
    elseif( draw_number < (third_number + second_number + first_number) ) then
        level = 1
    end

    return level
end

function draw()
    local respon = {}
    local code

    while(1) do 
        local login_number, err = red:scard(KEY_LOGIN_MEMBER_LIST)
	    if (not login_number) or (login_number == 0)then
            code = -2
            break
	    end

	    local win_phone,err = red:srandmember(KEY_LOGIN_MEMBER_LIST)
	    if not win_phone then
            code = -3
            break 
	    end


        local draw_number, err = red:scard(KEY_DRAW_MEMBER_LIST)
	    if not draw_number then
            draw_number = 0
	    end


	    local has_draw, err = red:sismember(KEY_DRAW_MEMBER_LIST, win_phone)
	    if (has_draw == 0) then
            local level = get_level(draw_number) 
            if(level == 0) then
                code = -4
                break
            end

	        local res, err = red:sadd(KEY_DRAW_MEMBER_LIST, win_phone)
	        if not res then
                code = -5
                break
	        end

	        red:hset(win_phone, 'level', level)

            respon['name'] = red:hget(win_phone, 'name')
            respon['order'] = red:hget(win_phone, 'order')

            respon['level'] = level
            respon['phone'] = win_phone

	        local res_rem, err = red:srem(KEY_LOGIN_MEMBER_LIST, win_phone)
	        if not res_rem then
                code = -6
	        end

            code = 0
            break
        else
            code = -7
            break
	    end
        
    end
    
    respon['code'] = code 
	ngx.say(cjson.encode(respon))	
end

function set_arg()
end

function get_award(level)
   local award 

   if(level == "3") then
       award = red:hget(SET_VALUE, 'field_6')
   elseif(level == "2") then
       award = red:hget(SET_VALUE, 'field_5')
   elseif(level == "1") then
       award = red:hget(SET_VALUE, 'field_4')
   end

   return award
end

function get_all_list()
    local arr = {}
    local name = {}
    local phone = {}
    local level = {}
    local award = {}

    local key
    
    if not args['list_type'] then
        nginx.say("error")
    end

    if (args['list_type'] == "all") then
        key = KEY_ALL_MEMBER_LIST
    elseif(args['list_type'] == "login") then
        key = KEY_LOGIN_MEMBER_LIST
    elseif(args['list_type'] == "draw") then
        key = KEY_DRAW_MEMBER_LIST 
    end
    
	local list,err = red:smembers(key)
	if not list then
		ngx.say("failed to smember")
	end
	local list_len = table.getn(list)
	for i=1, list_len do
        name[i] = red:hget(list[i], 'name') 
        phone[i] = list[i] 

        if(args['list_type'] == "draw") then
            level[i] = red:hget(list[i], 'level')
            award[i] = get_award(level[i])
        end
	end
    
    arr['name'] = name
    arr['phone'] = phone 

    if(args['list_type'] == "draw") then
        arr['level'] = level 
        arr['award'] = award
    end

    ngx.say(cjson.encode(arr))
end

function main()
	init_redis()	
	parse_postargs()

	local op_action = {
		["add"] = function() return add_new_user() end,
		["login"] = function() return login_user() end, 
		["draw"] = function() return draw() end, 
		["set"] = function() return set_arg() end, 
		["list"] = function() return get_all_list() end, 
	}

	op_name = args["opname"]
	if not op_action[op_name] then 
		ngx.say("get op_name error")		
	end

    ngx.log(ngx.ERR, op_name)
	op_action[op_name]()
    ngx.exit(ngx.HTTP_OK)
end


main()
