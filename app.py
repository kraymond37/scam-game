from flask import Flask
from flask import request
from waitress import serve
import re
import time

app = Flask(__name__)

# 邀请码格式
code_pattern = r'[a-zA-Z0-9]{6}'
# 地址格式
address_pattern = r'0x[0-9a-fA-F]{40}'

# 资金池
fund_pool = 0
# 投注周期
invest_period = 60
# 奖励系数
level_reward_scale = [0, 5, 6, 8, 10]
equal_level_reward_scale = 10

member_depth_limit = 15
upgrade_depth_limit = 10
max_depth = 1024

# 当前用户投注列表
# address
# freeze_amount
# free_amount
# start_time
# end_time
# static_bonus
# share_bonus
# level_bonus
user_invests_dict = {}

# 用户总投入列表
# {address: total}
user_in_dict = {}

# 邀请人列表, 用于向上搜索
# {address: parent}
parents_dict = {}

# 下级成员列表, 用于向下搜索
# {parent: {depth: invitee_array}}
members_dict = {}

# 下级成员数量列表
# {address: count}
member_count_dict = {}

# 有效下级成员数量列表
# {address: count}
valid_member_count_dict = {}

# 有效用户列表
# {address: bool}
valid_users_dict = {}

# 邀请码列表
# {invite_code: address}
address_dict = {}
# {address: invite_code}
invite_code_dict = {}

# 用户级别列表
# {address: level}
user_level_dict = {}

# 用户级别
LEVEL_0 = 0
LEVEL_1 = 1
LEVEL_2 = 2
LEVEL_3 = 3
LEVEL_4 = 4

# 错误码
ERROR_MISSING_ARG = 100
ERROR_INVALID_ARG = 101
ERROR_OPERATION_DENIED = 102
ERROR_NOT_EXIST = 103

# 默认/根节点地址和邀请码
root_address = '0xA5433A9C6f65FfeFD1F8edC7970216eDcbCe5Ac3'
root_code = 'connor'


def error_message(code, message):
    return {'code': code, 'msg': message}


def response(msg='OK', data=None):
    if data is None:
        return {'code': 0, 'msg': msg}
    else:
        return {'code': 0, 'msg': msg, 'data': data}


def bind_default_code():
    global address_dict
    global invite_code_dict
    global parents_dict
    global members_dict
    global member_count_dict
    global valid_users_dict
    global valid_member_count_dict
    global user_level_dict

    address_dict[root_code] = root_address
    invite_code_dict[root_address] = root_code

    parent = '0xFF'
    parents_dict[root_address] = parent

    depth_member_array = [[root_address]]
    members_dict[parent] = depth_member_array
    member_count_dict[parent] = 1

    members_dict[root_address] = []
    member_count_dict[root_address] = 0

    valid_users_dict[root_address] = False
    valid_member_count_dict[root_address] = 0

    user_level_dict[root_address] = LEVEL_0


def set_valid(address):
    global valid_users_dict
    global valid_member_count_dict

    if valid_users_dict[address]:
        return

    valid_users_dict[address] = True

    parent = parents_dict[address]
    for depth in range(0, member_depth_limit):
        if parent not in parents_dict:
            break
        valid_member_count_dict[parent] += 1
        parent = parents_dict[parent]


# 计算上级的分享奖励和节点奖励
def calc_reward(address):
    global user_invests_dict

    user_invest = user_invests_dict[address]
    self_bonus = user_invest['static_bonus'] + user_invest['share_bonus'] + user_invest['level_bonus']
    if self_bonus == 0:
        return

    parent = parents_dict[address]
    now = time.time()
    max_level = user_level_dict[address]
    level_count_list = [0, 0, 0, 0, 0]
    level_count_list[max_level] = 1
    nearest_equal_level_address = None
    should_stop = False
    for depth in range(0, max_depth):
        if parent not in invite_code_dict:
            break

        # 不是有效会员没有分享收益和节点奖励
        # 一个周期结束后没有继续投注就没有分享收益和节点奖励
        # 但还是应该统计一下级别, 否则没法计算上级的节点奖励
        has_reward = valid_users_dict[parent] is True or user_invests_dict[parent]['end_time'] >= now

        # 分享收益限15代以内
        if depth < member_depth_limit and has_reward:
            if depth == 0:
                user_invests_dict[parent]['share_bonus'] += self_bonus * 15 / 100
            elif depth == 1:
                user_invests_dict[parent]['share_bonus'] += self_bonus * 10 / 100
            elif depth == 2:
                user_invests_dict[parent]['share_bonus'] += self_bonus * 5 / 100
            elif 3 <= depth <= 9:
                user_invests_dict[parent]['share_bonus'] += self_bonus * 3 / 100
            elif 10 <= depth <= 14:
                user_invests_dict[parent]['share_bonus'] += self_bonus * 1 / 100

        # 节点奖励
        if not should_stop and user_level_dict[parent] >= LEVEL_1:
            level_bonus = 0

            # 正常节点奖励
            if user_level_dict[parent] > max_level:
                level_bonus = self_bonus * level_reward_scale[user_level_dict[parent]] / 100

            # 平级节点奖励, 仅限中级以上节点, 仅限一代
            # 只可能有一个, 即与address等级相同的第一个上级节点
            elif (nearest_equal_level_address is None
                  and user_level_dict[parent] > LEVEL_1
                  and user_level_dict[parent] == max_level
                  and user_level_dict[address] == max_level):

                nearest_equal_level_address = parent
                level_bonus = self_bonus * equal_level_reward_scale / 100

            # 被越级没奖励

            if has_reward:
                user_invests_dict[parent]['level_bonus'] += level_bonus

            max_level = max(max_level, user_level_dict[parent])
            level_count_list[user_level_dict[parent]] += 1

            # 如果已到最大等级, 除了平级节点不可能再有奖励, 如果已经找到平级节点或者不可能存在平级节点, 就可以停止了
            if max_level == LEVEL_4:
                if user_level_dict[address] != LEVEL_4 or nearest_equal_level_address is not None:
                    should_stop = True

        if depth >= member_depth_limit and should_stop:
            break

        parent = parents_dict[parent]


@app.route('/')
def hello_world():
    return 'This is a scam game! Please exit right away!'


@app.route('/test')
def test():
    return response(data=invite_code_dict)


@app.route('/invite_address/<string:invite_code>')
def get_inviter_address(invite_code):
    if invite_code not in address_dict:
        return error_message(ERROR_NOT_EXIST, 'invite code not exist')
    return response(data=address_dict[invite_code])


@app.route('/bind', methods=['POST'])
def bind():
    global address_dict
    global invite_code_dict
    global parents_dict
    global members_dict
    global member_count_dict
    global valid_users_dict
    global valid_member_count_dict
    global user_level_dict

    address = request.args.get('address', type=str)
    invite_code = request.args.get('invite_code', type=str)
    your_code = request.args.get('your_code', type=str)

    if address is None or invite_code is None or your_code is None:
        return error_message(ERROR_MISSING_ARG, 'missing args')

    if re.fullmatch(address_pattern, address) is None:
        return error_message(ERROR_INVALID_ARG, 'invalid address')

    if invite_code not in address_dict:
        return error_message(ERROR_NOT_EXIST, 'inviter not exist')

    if re.fullmatch(code_pattern, your_code) is None:
        return error_message(ERROR_INVALID_ARG, 'invalid invite code')

    if your_code in address_dict:
        return error_message(ERROR_OPERATION_DENIED, 'your code has been bond')

    address_dict[your_code] = address
    invite_code_dict[address] = your_code

    members_dict[address] = []
    member_count_dict[address] = 0

    parent = address_dict[invite_code]
    parents_dict[address] = parent
    for depth in range(0, member_depth_limit):
        if len(members_dict[parent]) <= depth:
            members_dict[parent].append([address])
        else:
            members_dict[parent][depth].append(address)
        member_count_dict[parent] += 1

        if parent not in parents_dict:
            break
        parent = parents_dict[parent]

    valid_users_dict[address] = False
    valid_member_count_dict[address] = 0

    user_level_dict[address] = LEVEL_0

    return response()


@app.route('/user/<string:address>')
def get_user(address):
    if re.fullmatch(address_pattern, address) is None:
        return error_message(ERROR_INVALID_ARG, 'invalid address')

    if address not in invite_code_dict:
        return error_message(ERROR_NOT_EXIST, 'user not exist')

    user = {'address': address,
            'invite_code': invite_code_dict[address],
            'inviter': '',
            'members': members_dict[address],
            'valid_member_count': valid_member_count_dict[address]}

    if parents_dict[address] in invite_code_dict:
        user['inviter'] = invite_code_dict[parents_dict[address]]

    if address not in user_invests_dict:
        return response(data=user)

    user['freeze_amount'] = user_invests_dict[address]['freeze_amount']
    user['free_amount'] = user_invests_dict[address]['free_amount']
    user['static_bonus'] = user_invests_dict[address]['static_bonus']
    user['share_bonus'] = user_invests_dict[address]['share_bonus']
    user['start_time'] = user_invests_dict[address]['start_time']
    user['end_time'] = user_invests_dict[address]['end_time']

    return response(data=user)


@app.route('/invest', methods=['POST'])
def invest():
    global user_invests_dict
    global user_in_dict
    global fund_pool

    address = request.args.get('address', type=str)
    value = request.args.get('value', type=float)
    if address is None or value is None:
        return error_message(ERROR_MISSING_ARG, 'missing args')

    if re.fullmatch(address_pattern, address) is None:
        return error_message(ERROR_INVALID_ARG, 'invalid address')

    if address not in invite_code_dict:
        return error_message(ERROR_OPERATION_DENIED, 'need to bind invite code first')

    if address in user_invests_dict:
        user_invest = user_invests_dict[address]
        if int(time.time() < user_invest['end_time']):
            return error_message(ERROR_OPERATION_DENIED, 'one invest a round')
        elif user_invest['end_time'] > 0:
            return error_message(ERROR_OPERATION_DENIED, 'need settlement first')

        min_invest = max(0.5, user_invest['freeze_amount'] / 4 * 70 / 100)
        max_invest = min(60, user_invest['freeze_amount'] * 5 / 4 + 5)
        if value < min_invest or value > max_invest:
            return error_message(ERROR_INVALID_ARG, 'value need to be between %s-%s' % (min_invest, max_invest))
        user_invest['freeze_amount'] += value
        user_invest['start_time'] = int(time.time())
        user_invest['end_time'] = user_invest['start_time'] + invest_period
        user_invests_dict[address] = user_invest
        user_in_dict[address] += value
    else:
        if value < 1 or value > 20:
            return error_message(ERROR_INVALID_ARG, 'value need to be between 1-20')
        current = int(time.time())
        user_invests_dict[address] = {'address': address,
                                      'free_amount': 0.0,
                                      'freeze_amount': float(value),
                                      'static_bonus': 0.0,
                                      'share_bonus': 0.0,
                                      'level_bonus': 0.0,
                                      'start_time': current,
                                      'end_time': current + invest_period}
        user_in_dict[address] = value
        set_valid(address)

    fund_pool += value
    return response()


@app.route('/settlement', methods=['POST'])
def settlement():
    global user_invests_dict

    address = request.args.get('address', type=str)
    if address is None:
        return error_message(ERROR_MISSING_ARG, 'missing args')

    if re.fullmatch(address_pattern, address) is None:
        return error_message(ERROR_INVALID_ARG, 'invalid address')

    if address not in user_invests_dict:
        return error_message(ERROR_OPERATION_DENIED, 'no invest')

    user_invest = user_invests_dict[address]
    if int(time.time()) < user_invest['end_time']:
        return error_message(ERROR_OPERATION_DENIED,
                             'not time (%s) to calculate' % time.asctime(time.localtime(user_invest['end_time'])))

    if user_invest['end_time'] == 0:
        return error_message(ERROR_OPERATION_DENIED, 'settlement done already')

    user_invest['static_bonus'] += user_invest['freeze_amount'] * 8 / 100
    user_invest['free_amount'] += user_invest['freeze_amount'] * 20 / 100
    user_invest['freeze_amount'] = user_invest['freeze_amount'] * 80 / 100
    user_invest['end_time'] = 0
    user_invests_dict['address'] = user_invest

    # 自己的分享收益和节点奖励是由下级结算时计算而来, 下面是计算上级的分享收益和节点奖励
    calc_reward(address)

    return response(data=user_invest)


@app.route('/withdraw', methods=['POST'])
def withdraw():
    global fund_pool
    global user_invests_dict

    address = request.args.get('address', type=str)
    if address is None:
        return error_message(ERROR_MISSING_ARG, 'missing args')

    if re.fullmatch(address_pattern, address) is None:
        return error_message(ERROR_INVALID_ARG, 'invalid address')

    if address not in user_invests_dict:
        return error_message(ERROR_OPERATION_DENIED, 'no invest')

    user_invest = user_invests_dict[address]
    send_value = (user_invest['static_bonus']
                  + user_invest['share_bonus']
                  + user_invest['level_bonus']
                  + user_invest['free_amount'])
    if send_value == 0:
        return error_message(ERROR_OPERATION_DENIED, 'your bonus is 0')

    user_invest['static_bonus'] = 0
    user_invest['share_bonus'] = 0
    user_invest['level_bonus'] = 0
    user_invest['free_amount'] = 0
    user_invests_dict['address'] = user_invest

    real_send_value = min(fund_pool, send_value)
    fund_pool -= real_send_value

    return response(msg='send to you %s eth' % real_send_value)


@app.route('/upgrade', methods=['POST'])
def upgrade_level():
    address = request.args.get('address', type=str)
    if address is None:
        return error_message(ERROR_MISSING_ARG, 'missing args')

    if re.fullmatch(address_pattern, address) is None:
        return error_message(ERROR_INVALID_ARG, 'invalid address')

    if address not in invite_code_dict:
        return error_message(ERROR_OPERATION_DENIED, 'user not exist')

    if user_level_dict[address] >= LEVEL_4:
        return error_message(ERROR_OPERATION_DENIED, 'level is already the max')

    valid_count = 0

    # LEVEL_0 → LEVEL_1
    if user_level_dict[address] == 0:

        # 自身投入不小于 10 eth
        if user_in_dict[address] < 10:
            return error_message(ERROR_OPERATION_DENIED, 'not enough invest')

        # 团队有效玩家不小于100人
        if valid_member_count_dict[address] < 100:
            return error_message(ERROR_OPERATION_DENIED, 'not enough valid members')

        # 推荐10个以上有效玩家
        for invitee in members_dict[address][0]:
            if valid_users_dict[invitee]:
                valid_count += 1
                if valid_count >= 10:
                    break
        if valid_count < 10:
            return error_message(ERROR_OPERATION_DENIED, 'not enough valid invitees')

    # LEVEL_n → LEVEL_(n+1)
    else:
        for invitee in members_dict[address][0]:
            if user_level_dict[invitee] >= user_level_dict[address]:
                valid_count += 1
                if valid_count >= 3:
                    break
                continue
            else:
                for depth, members in enumerate(members_dict[invitee]):
                    if depth >= upgrade_depth_limit - 1:
                        break
                    for member in members:
                        if user_level_dict[member] >= user_level_dict[address]:
                            valid_count += 1
                            break
                    if valid_count >= 3:
                        break
                if valid_count >= 3:
                    break
        if valid_count < 3:
            return error_message(ERROR_OPERATION_DENIED, 'dont amuse me')

    user_level_dict[address] += 1


if __name__ == '__main__':
    bind_default_code()
    serve(app, host='0.0.0.0', port=6868)
