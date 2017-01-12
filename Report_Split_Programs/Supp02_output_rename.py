"""
### CODE OWNERS: Aaron Burgess, Jason Altieri

### OBJECTIVE:
  Rename files on the fly given they have not
  been renamed using _all or _<digit>

### DEVELOPER NOTES:
  <none>
"""

import shutil
import sys
import re

from indypy.file_utils import IndyPyPath

_ANTI_PATTERN = r'(_all|_a_)(.+?\.|\.)(sas7bdat|sqlite|sas7bndx)'

def rename_files(directory, name_extension):
    """Target sas and sqlite files that do not feature
    an explicit name format"""
    path = IndyPyPath(directory)
    unwanted_files = path.collect_files_regex(_ANTI_PATTERN)
    all_ext_files = path.collect_files_extensions(['sas7bdat', 'sqlite', 'sas7bndx'])
    final_files = list(set(all_ext_files) - set(unwanted_files))
    for file in final_files:
        new_stem = file.stem + '_' + name_extension
        if file.suffix != '.sqlite':
            new_name = new_stem[:32]
        else:
            new_name = new_stem
        new_file = '{file}{ext}'.format(file=str(new_name), ext=file.suffix)
        shutil.move(str(file), str(file.parent / new_file))


if __name__ == '__main__':
    print("Starting file rename using extension {ext}".format(ext=sys.argv[2]))
    rename_files(sys.argv[1], sys.argv[2])
    print("Done converting files.")
