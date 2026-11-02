# SPDX-License-Identifier: AGPL-3.0-or-later
# Модуль Synapse: создавать комнаты, приглашать и публиковать комнаты может только админ
# Настройка (необязательно): config.service_accounts, список служебных учётных записей,
# которым разрешено создавать комнаты, приглашать и входить любым способом.
from synapse.module_api import ModuleApi, NOT_SPAM
from synapse.module_api.errors import Codes



class AdminOnly:
    def __init__(self, config: dict, api: ModuleApi):
        self._api = api
        self._service = set((config or {}).get("service_accounts") or [])
        api.register_spam_checker_callbacks(
            user_may_create_room=self.user_may_create_room,
            user_may_invite=self.user_may_invite,
            user_may_create_room_alias=self.user_may_create_room_alias,
            user_may_publish_room=self.user_may_publish_room,
            check_login_for_spam=self.check_login_for_spam,
        )

    @staticmethod
    def parse_config(config: dict) -> dict:
        return config

    async def _check(self, user_id: str):
        # Админ Synapse проходит, все остальные получают отказ M_FORBIDDEN
        if await self._api.is_user_admin(user_id):
            return NOT_SPAM
        return Codes.FORBIDDEN

    async def user_may_create_room(self, user_id: str, room_config=None):
        if user_id in self._service:
            return NOT_SPAM
        # DVChat: личный чат создаёт модуль dv_social; в конфиге запроса его одноразовая метка
        try:
            import dv_shared

            if isinstance(room_config, dict) and dv_shared.consume(
                room_config.get("dv_nonce")
            ):
                return NOT_SPAM
        except Exception:
            pass
        return await self._check(user_id)

    async def user_may_invite(self, inviter: str, invitee: str, room_id: str):
        if inviter in self._service:
            return NOT_SPAM
        # Админ приглашает кого угодно
        if await self._api.is_user_admin(inviter):
            return NOT_SPAM
        # DVChat: приглашение, которое модуль dv_social только что разрешил при создании чата
        try:
            import dv_shared

            if dv_shared.consume_invite(inviter, invitee, room_id):
                return NOT_SPAM
        except Exception:
            pass
        # DVChat: остальные могут только вернуть в ту же комнату того, кто из неё вышел,
        # и только если сами сейчас в этой комнате
        try:
            state = await self._api.get_room_state(
                room_id,
                [("m.room.member", invitee), ("m.room.member", inviter)],
            )
            e_invitee = state.get(("m.room.member", invitee))
            e_inviter = state.get(("m.room.member", inviter))
            if (
                e_invitee is not None
                and e_inviter is not None
                and e_invitee.content.get("membership") == "leave"
                and e_inviter.content.get("membership") == "join"
            ):
                return NOT_SPAM
        except Exception:
            pass
        return Codes.FORBIDDEN

    async def user_may_create_room_alias(self, user_id: str, room_alias):
        return await self._check(user_id)

    async def user_may_publish_room(self, user_id: str, room_id: str):
        return await self._check(user_id)

    async def check_login_for_spam(
        self,
        user_id: str,
        device_id,
        initial_display_name,
        request_info,
        auth_provider_id=None,
    ):
        if user_id in self._service:
            return NOT_SPAM
        # Админ может входить любым клиентом (Element и т.д.)
        if await self._api.is_user_admin(user_id):
            return NOT_SPAM
        # Остальные только из DVChat: приложение называет устройство "DVChat ..."
        if (initial_display_name or "").startswith("DVChat"):
            return NOT_SPAM
        return Codes.FORBIDDEN
