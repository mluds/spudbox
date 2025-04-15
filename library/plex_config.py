#!/usr/bin/python
# -*- coding: utf-8 -*-

DOCUMENTATION = '''
---
module: plex_config
short_description: Configure Plex Media Server libraries and settings
description:
    - Configures Plex Media Server library sections and server settings
options:
    plex_url:
        description:
            - URL of the Plex server
        required: true
        type: str
    username:
        description:
            - Plex account username
        required: false
        type: str
    password:
        description:
            - Plex account password
        required: false
        type: str
    token:
        description:
            - Plex authentication token
        required: false
        type: str
    access_url:
        description:
            - Custom access URL for the Plex server
        required: true
        type: str
    library_sections:
        description:
            - Library sections to configure
        required: false
        type: list
        elements: dict
        default: []
'''

EXAMPLES = '''
- name: Configure Plex server
  plex_config:
    plex_url: "http://localhost:32400"
    username: "{{ plex_username }}"
    password: "{{ plex_password }}"
    access_url: "https://plex.example.com:32400"
    library_sections:
      - name: "Movies"
        type: "movie"
        agent: "tv.plex.agents.movie"
        scanner: "Plex Movie"
        location: "/data/media/movies"
        language: "en-US"
'''

RETURN = '''
changed:
    description: Whether any changes were made
    type: bool
    returned: always
changes:
    description: List of changes that were made
    type: list
    returned: always
'''

from ansible.module_utils.basic import AnsibleModule
import traceback

try:
    from plexapi.server import PlexServer
    from plexapi.myplex import MyPlexAccount
    from plexapi.exceptions import NotFound
    HAS_PLEXAPI = True
except ImportError:
    HAS_PLEXAPI = False


def main():
    module = AnsibleModule(
        argument_spec=dict(
            plex_url=dict(type='str', required=True),
            username=dict(type='str', required=False),
            password=dict(type='str', required=False, no_log=True),
            token=dict(type='str', required=False, no_log=True),
            access_url=dict(type='str', required=True),
            library_sections=dict(
                type='list',
                elements='dict',
                required=False,
                default=[],
                options=dict(
                    name=dict(type='str', required=True),
                    type=dict(type='str', required=True, choices=['movie', 'show', 'music', 'photo']),
                    agent=dict(type='str', required=True),
                    scanner=dict(type='str', required=True),
                    location=dict(type='str', required=True),
                    language=dict(type='str', required=True)
                )
            ),
        ),
        supports_check_mode=True,
        required_one_of=[
            ('token', 'username')
        ]
    )

    if not HAS_PLEXAPI:
        module.fail_json(msg='The plexapi Python module is required')

    # Get module parameters
    plex_url = module.params['plex_url']
    username = module.params['username']
    password = module.params['password']
    token = module.params['token']
    access_url = module.params['access_url']
    library_sections = module.params['library_sections']

    changes = []
    changed = False

    try:
        # Authenticate with Plex
        if token:
            plex = PlexServer(plex_url, token)
        elif username and password:
            account = MyPlexAccount(username, password)
            token = account.authToken
            plex = PlexServer(plex_url, token)
        else:
            module.fail_json(msg='Either token or both username and password are required')

        # Configure library sections
        for section in library_sections:
            try:
                # Check if section already exists
                plex.library.section(section['name'])
            except NotFound:
                if not module.check_mode:
                    # Add section if it doesn't exist
                    plex.library.add(
                        name=section['name'],
                        type=section['type'],
                        agent=section['agent'],
                        scanner=section['scanner'],
                        location=section['location'],
                        language=section['language']
                    )
                changes.append(f"Added library section '{section['name']}'")
                changed = True

        # Check and update settings
        settings_changed = False

        # Enable filesystem events
        if plex.settings.fSEventLibraryUpdatesEnabled is not True:
            if not module.check_mode:
                plex.settings.fSEventLibraryUpdatesEnabled = True
                settings_changed = True
            changes.append("Enabled filesystem event library updates")
            changed = True

        # Set custom connections
        if plex.settings.customConnections != access_url:
            if not module.check_mode:
                plex.settings.customConnections = access_url
                settings_changed = True
            changes.append(f"Updated custom connections to '{access_url}'")
            changed = True

        # Save settings if changed
        if settings_changed and not module.check_mode:
            plex.settings.save()

        # Return results
        module.exit_json(
            changed=changed,
            changes=changes
        )

    except Exception as e:
        module.fail_json(msg=str(e), exception=traceback.format_exc())


if __name__ == '__main__':
    main()