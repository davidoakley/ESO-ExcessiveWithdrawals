import re
import shutil
import os
import sys

from _src import utils

utils.check_dependencies("ExcessiveWithdrawals", "## DependsOn:", True)
utils.check_dependencies("ExcessiveWithdrawals", "## OptionalDependsOn:", False)

VERSION = utils.get_tag()
if VERSION == "":
  print("🛑 No version tag found", file=sys.stderr)
  exit(1)

print(f"Version {VERSION}")

ADDON_VERSION = utils.convert_to_addon_version(VERSION)

print(f"AddOnVersion {ADDON_VERSION}")

if os.path.exists("_build/ExcessiveWithdrawals"):
  shutil.rmtree('_build/ExcessiveWithdrawals')

os.mkdir('_build/ExcessiveWithdrawals')

utils.copy(r'*.lua', '_build/ExcessiveWithdrawals')
utils.copy(r'*.txt', '_build/ExcessiveWithdrawals')
utils.copy(r'*.xml', '_build/ExcessiveWithdrawals')

# shutil.copytree('media', '_build/ExcessiveWithdrawals/media')
# shutil.copytree('lang', '_build/ExcessiveWithdrawals/lang')

with open('ExcessiveWithdrawals.txt', 'r') as inFile:
  NAVIGATOR_TXT = inFile.read()
  NAVIGATOR_TXT = re.sub(r'## Version: \w+', f"## Version: {VERSION}", NAVIGATOR_TXT)
  NAVIGATOR_TXT = re.sub(r'## AddOnVersion: \w+', f"## AddOnVersion: {ADDON_VERSION}", NAVIGATOR_TXT)
  with open('_build/ExcessiveWithdrawals/ExcessiveWithdrawals.txt', 'w') as outFile:
    outFile.write(NAVIGATOR_TXT)

with open('ExcessiveWithdrawals.lua', 'r') as inFile:
  lua = inFile.read()
  lua = re.sub(r'appVersion = "[^"]*"', f'appVersion = "{VERSION}"', lua)
  with open('_build/ExcessiveWithdrawals/ExcessiveWithdrawals.lua', 'w') as outFile:
    outFile.write(lua)

shutil.make_archive(f"_build/ExcessiveWithdrawals-v{VERSION}", 'zip', root_dir='_build', base_dir='ExcessiveWithdrawals')
