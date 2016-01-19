"""
### CODE OWNERS: Aaron Burgess

### OBJECTIVE:
  Rename files on the fly given they have not
  been renamed using _all or _<digit>

### DEVELOPER NOTES:
  <none>
"""

import os
import sys
import re

sys.path.append(r"S:\Misc\_IndyMacros\Code\python\indypy")

from file_utils import IndyPyPath

_ANTI_PATTERN = r'.*(_all|_\d+)\.(sas7bdat|sqlite|sas7bndx)'
_EXT_PATTERN = r'^(all|\d+)$'


def rename_files(directory, name_extension):
    """Target sas and sqlite files that do not feature
    an explicit name format"""
    if not re.search(_EXT_PATTERN, name_extension, re.I):
        raise ValueError("Name extensions must be 'all' or positive integer")
    path = IndyPyPath(directory)
    unwanted_files = path.collect_files_regex(_ANTI_PATTERN)
    all_ext_files = path.collect_files_extensions(['sas7bdat', 'sqlite', 'sas7bndx'])
    final_files = list(set(all_ext_files) - set(unwanted_files))
    for file in final_files:
        new_name = file.parent / file.stem
        new_file = '{file}_{name}{ext}'.format(file=str(new_name),
                                               name=name_extension, ext=file.suffix)
        os.rename(str(file), new_file)


if __name__ == '__main__':
    print("Starting file rename using extension {ext}".format(ext=sys.argv[2]))
    rename_files(sys.argv[1], sys.argv[2])
    print("Done converting files.")
