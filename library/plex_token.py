#!/usr/bin/python
# -*- coding: utf-8 -*-

DOCUMENTATION = '''
---
module: plex_token
short_description: Retrieve Plex authentication token
description:
    - Retrieves a Plex authentication token using username and password
    - Sets the token as an Ansible fact that can be used in subsequent tasks
options:
    username:
        description:
            - Plex account username
        required: true
        type: str
    password:
        description:
            - Plex account password
        required: true
        type: str
    fact_name:
        description:
            - Name of the Ansible fact to store the token
        required: false
        type: str
        default: plex_auth_token
'''

EXAMPLES = '''
- name: Get Plex authentication token
  plex_token:
    username: "{{ plex_username }}"
    password: "{{ plex_password }}"
    fact_name: "my_plex_token"
  no_log: true

- name: Use the token in subsequent tasks
  plex_config:
    plex_url: "http://localhost:32400"
    token: "{{ my_plex_token }}"
    access_url: "https://plex.example.com:32400"
'''

RETURN = '''
fact_name:
    description: Name of the Ansible fact containing the token
    type: str
    returned: always
token:
    description: The Plex authentication token (only returned when in non-secure logs)
    type: str
    returned: always
'''

from ansible.module_utils.basic import AnsibleModule
import traceback

try:
    from plexapi.myplex import MyPlexAccount
    HAS_PLEXAPI = True
except ImportError:
    HAS_PLEXAPI = False


def main():
    module = AnsibleModule(
        argument_spec=dict(
            username=dict(type='str', required=True),
            password=dict(type='str', required=True, no_log=True),
            fact_name=dict(type='str', required=False, default='plex_token'),
        ),
        supports_check_mode=True
    )

    if not HAS_PLEXAPI:
        module.fail_json(msg='The plexapi Python module is required')

    # Get module parameters
    username = module.params['username']
    password = module.params['password']
    fact_name = module.params['fact_name']

    try:
        # Authenticate with Plex to get token
        account = MyPlexAccount(username, password)
        token = account.authToken

        # Set Ansible fact with the token
        module.exit_json(
            changed=False,
            ansible_facts={fact_name: token},
            fact_name=fact_name,
            token=token
        )

    except Exception as e:
        module.fail_json(msg=str(e), exception=traceback.format_exc())


if __name__ == '__main__':
    main()
