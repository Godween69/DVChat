# SPDX-License-Identifier: AGPL-3.0-or-later
# DVChat: общие разрешения между модулями admin_only и dv_social (живут в памяти Synapse)
import secrets
import time

_TTL = 60  # секунд
_nonces = {}
_invites = {}


def _purge():
    now = time.time()
    for store in (_nonces, _invites):
        for key in [k for k, exp in store.items() if exp < now]:
            store.pop(key, None)


def new_nonce():
    """Метка для создания комнаты: знает только модуль dv_social."""
    _purge()
    n = secrets.token_urlsafe(16)
    _nonces[n] = time.time() + _TTL
    return n


def consume(nonce):
    _purge()
    if isinstance(nonce, str) and nonce in _nonces:
        del _nonces[nonce]
        return True
    return False


def allow_invite(inviter, invitee, room_id):
    _purge()
    _invites[(inviter, invitee, room_id)] = time.time() + _TTL


def consume_invite(inviter, invitee, room_id):
    _purge()
    key = (inviter, invitee, room_id)
    if key in _invites:
        del _invites[key]
        return True
    return False
