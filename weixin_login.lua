local http = require "resty.http"
local cjson = require "cjson";
local redis = require "resty.redis";

REDIS_SERVER_IP = "127.0.0.1"
REDIS_SERVER_PORT = 6379
REDIS_TIMEOUT = 1000

KEY_ALL_MEMBER_LIST = 'all_member_list'
KEY_LOGIN_MEMBER_LIST = 'login_member_list'
KEY_DRAW_MEMBER_LIST = 'draw_member_list'

SET_VALUE = 'draw_set_value'

USER_STEP_NEW = 0
USER_STEP_MENU = 100
USER_STEP_FIRST = 1
USER_STEP_SECOND = 2 
USER_STEP_THIRD = 3 
USER_STEP_FOUR = 4
USER_STEP_FIVE = 5  --module
USER_STEP_SIX = 6 
USER_STEP_SEVEN = 7
USER_STEP_EIGHT = 8 
USER_STEP_NINE = 9 

USER_STEP_EXIT = 50 

ADMIN_STEP_MEMBER_COUNT = 11

ADMIN_STEP_PRIZE_FIRST = 121 
ADMIN_STEP_PRIZE_SECOND = 122
ADMIN_STEP_PRIZE_THIRD = 123
ADMIN_STEP_PRIZE_FOUR = 125
ADMIN_STEP_PRIZE_MODULE = 124

ADMIN_STEP_2 = 13 
ADMIN_STEP_3 = 14 

MEMBER_COUNT = 50

function init_redis()
	red = redis:new()
	red:set_timeout(REDIS_TIMEOUT)

	local ok, err = red:connect(REDIS_SERVER_IP, REDIS_SERVER_PORT)
	if not ok then
		ngx.log(ngx.ERR, err)
	end
end

function close_redis()
	local ok, err = red:setkeepalive(10000, 100)
end


function response_message(open_id, res_content)
    res_message = string.format("\
        <xml><ToUserName><![CDATA[%s]]></ToUserName>\
        <FromUserName><![CDATA[huoku_life]]></FromUserName>\
        <CreateTime>12345678</CreateTime>\
        <MsgType><![CDATA[text]]></MsgType>\
        <Content><![CDATA[%s]]></Content></xml>", open_id, res_content)
    ngx.say(res_message)
end

function verify_member_count(order)
    if (order > MEMBER_COUNT) then
        return false
    end
    return true
end

function login_user(open_id, phone)
    local detail = ""

    local login_count = red:scard(KEY_LOGIN_MEMBER_LIST)
    if not login_count then
        login_count = 0
    end

    order = login_count + 1;
    if (not verify_member_count(order)) then
        order = -1
        detail = "超出最大成员数量限制"
    else
        --更新成员登录序列
        red:hset(open_id, 'order', order)
        --添加成员到抽奖池
	    local res, err = red:sadd(KEY_LOGIN_MEMBER_LIST, open_id)
    end

    --order = 1
    return order,detail
end

function get_access_tooken()
    local httpc = http.new()

    local url = string.format("https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=%s&secret=%s", app_id, app_secret)
    local res, err = httpc:request_uri(url, {
        method = "GET",
        ssl_verify = false
    })

    if not res then
        ngx.log(ngx.ERR, "failed to request: ", err)
        return
    end
    res_table = cjson.decode(res.body)
    tooken = res_table['access_token']
    http:close()
    
    return tooken 
end

function update_user_draw(user_open_id, level)
    red:hset(user_open_id, "draw", level)
	res, err = red:sadd(KEY_DRAW_MEMBER_LIST, user_open_id)
    res, err = red:srem(KEY_LOGIN_MEMBER_LIST, user_open_id)
end

function update_user_phone(open_id, phone, role)
    red:hset(open_id, "phone", phone)
    red:hset(open_id, "role", role)
    --red:hset(open_id, "step", USER_STEP_SECOND)
    prize = red:hget(open_id, "prize")
    if not prize then
        red:hset(open_id, "prize", 0)
    end
end

function get_user_phone(open_id)
    return red:hget(open_id, "phone")
end

function get_step(open_id)
    local step
    local res = red:exists(open_id)
    if (not res) or (res == 0) then
        step = 0
    else
        step = tonumber(red:hget(open_id, "step"))
    end
    return step
end

function get_role(open_id)
    role = red:hget(open_id, "role")

    return role
end

function get_draw(open_id)
    local number = red:hget(open_id, "draw")
    return red:hget(open_id, "draw")
end

function get_draw_level(level)
    res_content = ''
    draw_member_lists = red:smembers(KEY_DRAW_MEMBER_LIST) 
    for key, open_id in pairs(draw_member_lists) do
        phone = get_user_phone(open_id)
        nickname = get_user_nickname(open_id)
        draw_level = get_draw(open_id)
        if(tonumber(draw_level) == level) then
            res_content = string.format("%s    手机号码:%s 微信昵称:%s\n", res_content, phone, nickname)
        end
    end

    return res_content
end

function get_all_draw_info()
    res_content = ''
    first_prize = get_draw_level(1)
    if (first_prize == '') then
        res_content = "没有获取中奖信息..."
    else
        res_content = string.format('一等奖:\n  %s', get_draw_level(1) )
        res_content = string.format('%s\n二等奖:\n  %s', res_content, get_draw_level(2) )
        res_content = string.format('%s\n三等奖:\n  %s', res_content, get_draw_level(3) )
    end
    res_content = string.format('%s\n\n回复0: 返回主菜单', res_content)
    set_user_step(open_id, USER_STEP_MENU)

    return res_content
end

function is_exist_open_id(open_id)
    res = red:exists(open_id)
    if (res == 0) then
        return false
    else
        return true
    end
end

function get_user_message(open_id)
    local tooken = get_access_tooken()
    local step = USER_STEP_FIRST

    local httpc = http.new()

    local url = string.format("https://api.weixin.qq.com/cgi-bin/user/info?access_token=%s&openid=%s&lang=zh_CN", tooken, open_id)
    local res, err = httpc:request_uri(url, {
        method = "GET",
        ssl_verify = false
        --headers = {
        --    ["Content-Type"] = "application/x-www-form-urlencoded",
        --}
    })
    if not res then
        ngx.log(ngx.ERR, "failed to request: ", err)
        return
    end
    res_table = cjson.decode(res.body)

    if not is_exist_open_id(open_id) then
        red:hset(open_id, "step", step)
        red:hset(open_id, "draw", 0)
    end

    if res_table then
        ngx.log(ngx.ERR, res.body)
        for key, value in pairs(res_table) do 
            red:hset(open_id, key, value)
        end
    end
end

function verify_phone(open_id, content)
    local role = 0
    
    if (tonumber(content) == nil) then
        res_content = "手机号码格式错误"
    else
        order,detail = login_user(open_id, content)
        if (order < 0) then
            res_content = detail 
        else
            if(order == 1) then
                --res_content = "你是第一位登录人员,默认为管理员身份。\n回复1 设置抽奖成员人数\n回复2 设置抽奖奖品信息\n回复3 设置抽奖时间\n回复4 设置抽奖模式\nps:如果你不是管理员回复5 在管理员登录后重新扫码登录。\n"
                res_content = "你是第一位登录人员,默认为管理员身份。\n\n回复0 进入抽奖设置主菜单"
                role = 1 
            else
                if vaild_time() then
                    res_content = "登录成功\n回复1: 获取奖品信息 回复2：获取你中奖信息(在抽奖结束后)"
                else
                    set_time = red:hget(SET_VALUE, "draw_time")
                    res_content = string.format("登录成功,抽奖开始时间为:%s, 回复1: 获取奖品信息 回复2：获取你中奖信息(在抽奖结束后)", set_time)
                end
            end
            update_user_phone(open_id, content, role)
            set_user_step(open_id, USER_STEP_MENU)
        end
    end

    return res_content
end

function set_user_step(open_id, step)
    red:hset(open_id, "step", step)
end

function set_members_count(member_count)
    red:hset(SET_VALUE, "member_count", member_count)
end

function update_draw_status(prize_level)
    local field = string.format("%d_status", prize_level)
    red:hset(SET_VALUE, field, 1)
end

function get_draw_status(prize_level)
    local field = string.format("%d_status", prize_level)
    local value = tonumber(red:hget(SET_VALUE, field))
    if(value == 1) then
        return false
    else
        return true
    end
end

function get_login_user()
    local i = 1 
    local res_content
    open_ids = red:smembers(KEY_LOGIN_MEMBER_LIST) 
    if open_ids then
        res_content = "已经登录成员列表\n"
        for key, open_id in pairs(open_ids) do
            phone = get_user_phone(open_id)
            nickname = get_user_nickname(open_id)
            res_content = string.format("%s%s)号码:%s,昵称:%s\n", res_content, i, phone, nickname)
            i = i + 1
        end
    else
        res_content = "还没有成员登录"
    end

    res_content = string.format("%s\n回复0 进入主菜单", res_content)
    set_user_step(open_id, USER_STEP_MENU)

    return res_content
end

function get_draw_set_info(role)
    member_count = red:hget(SET_VALUE, "member_count")
    prize_1_name = red:hget(SET_VALUE, "prize_1_name")
    prize_1_number = red:hget(SET_VALUE, "prize_1_number")
    prize_2_name = red:hget(SET_VALUE, "prize_2_name")
    prize_2_number = red:hget(SET_VALUE, "prize_2_number")
    prize_3_name = red:hget(SET_VALUE, "prize_3_name")
    prize_3_number = red:hget(SET_VALUE, "prize_3_number")
    prize_module = red:hget(SET_VALUE, "draw_module")

    if(prize_module == "1") then
        module = "抽奖模式"
    else
        module = "摇奖模式"
    end

    if(role == 1) then
        res_content = string.format("抽奖成员数量%s\n一等奖:%s  数量:%s\n二等奖:%s 数量:%s\n 三等奖:%s  数量:%s\n抽奖模式:%s", 
                        member_count, prize_1_name, prize_1_number, prize_2_name, prize_2_number, prize_3_name, prize_3_number, module)
    else
        res_content = string.format("一等奖:%s 数量:%s\n二等奖:%s 数量:%s\n三等奖:%s 数量:%s\n", 
                        prize_1_name, prize_1_number, prize_2_name, prize_2_number, prize_3_name, prize_3_number)
    end

    return res_content
end

function del_user_info(open_id)
    red:del(open_id)
    red:srem(KEY_LOGIN_MEMBER_LIST, open_id)
end

function admin_set_2(open_id, content)
    content = tonumber(content)
    if(content == 1) then
        set_user_step(open_id, USER_STEP_FOUR)
        res_content = "请输入抽奖成员数目"
    elseif(content == 2) then
        set_user_step(open_id, USER_STEP_THIRD)
        res_content = '请输入奖品信息，按照以下格式进行回复,\n\n奖品等级:奖品名称:奖品数量\n\n例如设置一等奖为iPhone6 奖品数量为3回复如下信息\n\n1:iPhone6:3'
    elseif(content == 3) then
        res_content = string.format('设置抽奖时间,\n 例如设置抽奖时间为晚上8点，回复 "20:00"')
        set_user_step(open_id, USER_STEP_SIX)
    elseif(content == 4) then
        res_content = string.format("回复1管理人员抽奖，回复2抽奖人员使用摇一摇抽奖")
        set_user_step(open_id, USER_STEP_FIVE)
    elseif(content == 5) then
        --del_user_info(open_id)
        res_content = get_draw_set_info(ioen_id, 1)
        --res_content = "请在管理员登录后， 重新扫描二维码登录"
    elseif(content == 6) then
        res_content = get_login_user() 
    elseif(content == 7) then
        res_content = start_draw(open_id)
    elseif(content == 8) then
        res_content =  get_all_draw_info()
    elseif(content == 11) then
        res_content = "请取消订阅，管理员登录后，重新扫描二维码登录"
        del_user_info(open_id)
        set_user_step(open_id, USER_STEP_EXIT)
    end

    return res_content
end

function reset_prize_info(open_id)
    red:hset(open_id, "step", USER_STEP_SECOND)
    res_content = "回复1 设置抽奖成员人数\n回复2 设置抽奖奖品信息\n回复3 设置抽奖时间\n回复4 设置抽奖模式\n"

    return res_content
end

function get_draw_module()
    return red:hget(SET_VALUE, "draw_module")
end

function start_draw(open_id)
    res_content = ""
    draw_module = get_draw_module()
     
    --if not vaild_time() then
    if vaild_time() then
        set_time = red:hget(SET_VALUE, "draw_time")
        res_content = string.format("抽奖时间为%s, 请在指定时间后进行抽奖, 回复0进入主菜单", set_time)
        set_user_step(open_id, USER_STEP_MENU)
    else
        if(draw_module == "1") then
            res_content = "回复3: 抽取三等奖户\n 回复2:抽奖二等奖用户\n 回复1:抽取一等奖用户\n\n 回复0:返回主菜单"
            set_user_step(open_id, USER_STEP_NINE)
        else
            res_content = "摇奖模式开启，已登录用户可以使用摇一摇抽奖, 回复1查看已中奖信息"
        end
    end

    return res_content
end

function get_prize_num(level)
    prize_number = 0
    key = string.format("prize_%d_number", level)
    prize_number = red:hget(SET_VALUE, key)

    return prize_number
end

function string2time(timeString) 
    local Y = string.sub(timeString , 1, 4)  
    local M = string.sub(timeString , 6, 7)  
    local D = string.sub(timeString , 9, 10)  
    local H = string.sub(timeString , 12, 13)  
    local m = string.sub(timeString , 15, 16)  
    return os.time({year=Y, month=M, day=D, hour=H,min=m,sec=0})  
end 

function vaild_time()
    set_time = red:hget(SET_VALUE, "draw_time")
    local cdate=os.date("%Y-%m-%d %H:%M:%S");
    local cur_time = os.time()

    draw_time = string.sub(cdate, 0, 11)
    draw_time = string.format("%s%s:00", draw_time, set_time)
    res_time = string2time(draw_time)
    
    if(res_time > cur_time) then
        return false
    else
        return true
    end
end

function get_user_phone(open_id)
    return red:hget(open_id, "phone")
end

function get_user_nickname(open_id)
    return red:hget(open_id, "nickname")
end

function draw_from_login_members(draw_number)
    local res_content = ""

    members = red:srandmember(KEY_LOGIN_MEMBER_LIST, draw_number)
    for k,open_id in pairs(members) do
        update_user_draw(open_id, content)

        phone = get_user_phone(open_id)
        nickname = get_user_nickname(open_id)
        res_content = string.format("%s手机号码%s,昵称%s\n", res_content, phone, nickname)
    end

    return res_content 
end

function menu_list(open_id)
    set_user_step(open_id, USER_STEP_SECOND)
    res_content = "回复1 设置抽奖成员人数\n\
回复2 设置抽奖奖品信息\n\
回复3 设置抽奖时间\n\
回复4 设置抽奖模式\n\
回复5:查看已设置抽奖信息\n\
回复6:查看已登录人员\n\
回复7:开始抽奖\n\
回复8:查看中奖信息"

    return res_content
end


function admin_draw(open_id, content)
    res_message = ""
    prize_level = tonumber(content) 
    if(prize_level == 0) then
        res_content = menu_list(open_id)
        return res_content
    end

    draw_module = get_draw_module()
    if(draw_module ~= "1") then
        res_message = "本次设置为摇奖模式"
    else
        if (prize_level == 3) or (prize_level == 2) or (prize_level == 1) then
            if get_draw_status(prize_level) then
                prize_num = get_prize_num(prize_level)
                user = draw_from_login_members(prize_num)
                res_message = string.format("%d等奖得奖用户:\n%s\n\n\n回复0进入主菜单", content, user)
                ngx.log(ngx.ERR, "test")
                update_draw_status(prize_level)
            else
                prize_info = get_draw_level(prize_level)
                res_message = string.format("%d等奖得奖用户:\n%s\n\n\n回复0进入主菜单", prize_level, prize_info)
            end
        end
    end
    
    return res_message
end

function admin_set_prize_time(open_id, content)
    red:hset(SET_VALUE, "draw_time", content)
    local res_content = string.format("已成功设置抽奖时间为 %s\n\n回复0 进入主菜单", content)

    set_user_step(open_id, USER_STEP_MENU)
    return res_content
end

function admin_set_prize_module(open_id, content)
    red:hset(SET_VALUE, "draw_module", content)
    local res_content

    prize_module = tonumber(content)
    if(prize_module == nil) then
        res_contet = "输入错误，请重新输入"
    else
        if(prize_module == 1) then
            module = "抽奖模式"
            res_content = string.format("已成功设置抽奖类型:%s\n\n回复0 进入主菜单", module)
        else
            module = "摇奖模式"
            res_content = string.format("已成功设置抽奖类型:%s\n\n回复0 进入主菜单", module)
        end
        set_user_step(open_id, USER_STEP_MENU)
    end
    return res_content
end


--切分字符串
function lua_string_split(str, split_char)
    local sub_str_tab = {};
    while (true) do
        local pos = string.find(str, split_char);
        if (not pos) then
            sub_str_tab[#sub_str_tab + 1] = str;
            break;
        end
        local sub_str = string.sub(str, 1, pos - 1);
        sub_str_tab[#sub_str_tab + 1] = sub_str;
        str = string.sub(str, pos + 1, #str);
    end

    return sub_str_tab;
end

function set_prize(prize_level, prize_name, prize_count)
    key_1 = string.format("prize_%d_name", prize_level)
    key_2 = string.format("prize_%d_number", prize_level)

    red:hset(SET_VALUE, key_1, prize_name)
    red:hset(SET_VALUE, key_2, prize_count)
end

function admin_set_member_count(open_id, content)
    set_user_step(open_id, USER_STEP_MENU)
    set_members_count(content)
    res_content = string.format("已成功设置抽奖成员人数为%s\n \n回复0 进入主菜单\n", content)

    return res_content
end


function admin_set_prize(open_id, content)
    if(content == "1") then
        res_content = get_draw_set_info()
        res_content = string.format("成功设置中奖信息\n%s\n回复0 进入主菜单\n", res_content)
        set_user_step(open_id, USER_STEP_MENU)
    else
        str_table = lua_string_split(content, ":")
        prize_level = str_table[1]
        prize_name = str_table[2]
        prize_count = str_table[3]
        if(prize_name == nil or prize_count == nil or prize_level == nil) then
            res_content = "输入错误，请重新输入"
            return res_content
        end

        set_prize(prize_level, prize_name, prize_count)

        res_content = string.format("已成功设置%d等奖,奖品信息为:\n%s 奖品个数:%s\n请继续按照格式输入奖品信息或回复1:结束输入", prize_level, prize_name, prize_count)
    end
    return res_content

    --if(level == 1) then
    --    res_content = string.format("已成功设置%d等奖奖品:\n%s 数量%s\n请回复设置%d等奖奖品名称和数量", level, prize_name, prize_count, level+1)
    --    set_user_step(open_id, ADMIN_STEP_PRIZE_SECOND)
    --elseif (level == 2) then
    --    res_content = string.format("已成功设置%d等奖奖品:%s 数量%s, 请设置%d等奖奖品名称和数量", level, prize_name, prize_count, level+1)
    --    set_user_step(open_id, ADMIN_STEP_PRIZE_THIRD)
    --elseif (level == 3) then
    --    res_content = string.format("已成功设置%d等奖奖品:%s 数量%s , 回复1管理人员抽奖，回复2抽奖人员使用摇一摇抽奖", level, prize_name, prize_count)
    --    set_user_step(open_id, ADMIN_STEP_PRIZE_MODULE)
    --elseif (level == 4) then
    --    res_content = string.format("回复1管理人员抽奖，回复2抽奖人员使用摇一摇抽奖")
    --    set_user_step(open_id, ADMIN_STEP_PRIZE_MODULE)
    --end

end

function get_prize_name(level)
    local filed_name = string.format("prize_%s_name", level)
    return red:hget(SET_VALUE, filed_name)
end

function get_draw_info(open_id, content)
    local res_content
    content = tonumber(content)
    if(content == 1) then
        res_content = get_draw_set_info(0)
    else
        res = get_draw(open_id)
        if(res ~= "0") then
            prize_name = get_prize_name(res)
            res_content = string.format(">>>恭喜你获得%s等奖 %s", res, prize_name)
        else
            res_content = "没有你的中奖信息。"
        end
    end

    return res_content
end

function text_dispose(post_body, open_id)
    local res 
    local step

    step = get_step(open_id)
    if (step == USER_STEP_NEW) then
        res_content = "请输入手机号码 参与抽奖活动"
        get_user_message(open_id)
        response_message(open_id, res_content)
        return 
    end

    --get event type
    str_start, str_end = string.find(post_body, "<Content>")
    str = string.sub(post_body, str_end+10, -1)

    str_start, str_end = string.find(str, "</Content>")
    content = string.sub(str, 0, str_start-4)

    if(step == USER_STEP_FIRST) then
        res_content = verify_phone(open_id, content)
    elseif(step == USER_STEP_EXIT) then
        res_content = "请稍后重新扫码登录" 
    else
        role = get_role(open_id)
        if (tonumber(role) == 1) then
            if(step == USER_STEP_SECOND) then
                res_content = admin_set_2(open_id, content)
            elseif(step == USER_STEP_THIRD) then
                res_content = admin_set_prize(open_id, content)
            elseif(step == USER_STEP_FOUR) then
                res_content = admin_set_member_count(open_id, content)
            elseif(step == USER_STEP_FIVE) then
                res_content = admin_set_prize_module(open_id, content)
            elseif(step == USER_STEP_SIX) then
                res_content = admin_set_prize_time(open_id, content)
            elseif(step == USER_STEP_SEVEN) then
                res_content = get_draw_set_info(1)
            elseif(step == USER_STEP_EIGHT) then
                res_content = get_login_user() 
            elseif(step == USER_STEP_NINE) then
                res_content = admin_draw(open_id, content)
            elseif(step == USER_STEP_MENU) then
                res_content = menu_list(open_id)
            end
        else
            res_content = get_draw_info(open_id, content)
        end
    end

    response_message(open_id, res_content)
end

function event_dispose(post_body, open_id)
    --get event type
    str_start, str_end = string.find(post_body, "<Event>")
    str = string.sub(post_body, str_end+10, -1)

    str_start, str_end = string.find(str, "</Event>")
    event_type = string.sub(str, 0, str_start-4)

    if (event_type == "subscribe") then
        text_dispose(post_body, open_id)
        --res_content = "请输入手机号码"
        --get_user_message(open_id)
        --response_message(open_id, res_content)
    elseif(event_type == "unsubscribe") then
        del_user_info(open_id) 
        ngx.log(ngx.ERR, "unsubscribe")
    end
end

-- 绑定微信URL
function bind_wechat_url()
    local arg = ngx.req.get_uri_args()
    for k,v in pairs(arg) do
        ngx.log(ngx.ERR, "[GET]  key:", k, " v:", v)
    end

    ngx.say(arg['echostr'])
end

function main()
	init_redis()	

    local post_body 

    ngx.req.read_body()
    local arg = ngx.req.get_post_args()
    for k,v in pairs(arg) do
        post_body = k
        ngx.log(ngx.ERR, post_body)
    end
    
    -- get message type
    str_start, str_end = string.find(post_body, "<MsgType>")
    message_type_str = string.sub(post_body, str_end+10, -1)
    str_start, str_end = string.find(message_type_str, "</MsgType>")
    message_type = string.sub(message_type_str, 0, str_start-4)

    -- get open_id 
    str_start, str_end = string.find(post_body, "<FromUserName>")
    str = string.sub(post_body, str_end+10, -1)

    str_start, str_end = string.find(str, "</FromUserName>")
    open_id = string.sub(str, 0, str_start-4)

    --get open_id

    if(message_type == "text") then
        text_dispose(post_body, open_id)
    elseif(message_type == "event") then
        event_dispose(post_body, open_id)
    end
    ngx.exit(ngx.HTTP_OK)
end

main()
