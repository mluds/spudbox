#!/usr/bin/python
# -*- coding: utf-8 -*-

# Save this file as filter_plugins/pbkdf2_hash.py in your Ansible project

from __future__ import absolute_import, division, print_function
__metaclass__ = type

import base64
import os

try:
    # Python 3.4+
    from hashlib import pbkdf2_hmac
except ImportError:
    # Fallback for older Python versions
    from backports.pbkdf2 import pbkdf2_hmac

class FilterModule(object):
    """Tautulli password hashing filters."""

    def filters(self):
        """Return the filter mapping."""
        return {
            'pbkdf2_hash': self.pbkdf2_hash,
        }

    def pbkdf2_hash(self, password, iterations=600000, salt=None):
        """
        Create a PBKDF2 hash of a password in Tautulli format.
        
        Args:
            password: The password to hash
            iterations: Number of iterations (default: 600000)
            salt: Optional salt (will generate random salt if None)
            
        Returns:
            String in format PBKDF2$sha256$iterations$salt$hash
        """
        if not salt:
            salt = os.urandom(16)
        elif isinstance(salt, str):
            # If salt is provided as a string, use it
            try:
                salt = base64.b64decode(salt)
            except:
                # If not base64, use as raw bytes
                salt = salt.encode('utf-8')
                
        # Generate the hash
        hash_bin = pbkdf2_hmac('sha256', password.encode('utf-8'), salt, iterations)
        
        # Convert binary values to base64
        salt_b64 = base64.b64encode(salt).decode('utf-8')
        hash_b64 = base64.b64encode(hash_bin).decode('utf-8')
        
        # Return the formatted hash
        return f"PBKDF2$sha256${iterations}${salt_b64}${hash_b64}"
