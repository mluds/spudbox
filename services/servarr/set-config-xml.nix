{ pkgs }:

# Set elements of a Sonarr/Radarr config.xml to the contents of secret files,
# so the values never appear on a command line (xmlstarlet -v would put them
# in /proc/<pid>/cmdline, readable by every local user):
#
#   set-config-xml FILE ELEMENT=SECRET_FILE...
#
# ELEMENT is a path below the root, e.g. Authentication/Password; missing
# elements are created. The file is rewritten in place, keeping its mode.
pkgs.writers.writePython3Bin "set-config-xml" { } ''
  import sys
  import xml.etree.ElementTree as ET

  path = sys.argv[1]
  tree = ET.parse(path)
  for arg in sys.argv[2:]:
      element, secret_file = arg.split("=", 1)
      with open(secret_file) as f:
          value = f.read().strip()
      node = tree.getroot()
      for tag in element.split("/"):
          child = node.find(tag)
          if child is None:
              child = ET.SubElement(node, tag)
          node = child
      node.text = value
  tree.write(path, encoding="utf-8")
''
