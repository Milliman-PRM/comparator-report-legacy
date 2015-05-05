"""
### CODE OWNERS: Shea Parkes

### OBJECTIVE:
  Stage data drive folders for postboarding work.

### DEVELOPER NOTES:
  This also code-gens a simple SAS script as well.
"""
import os
import re
import datetime

from pathlib import Path


# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================


def get_path_current():
    """Determine the path of this file"""
    try:
        return Path(os.path.realpath(__file__)).parent
    except NameError:
        # Likely running interactively
        return Path(os.getcwd())


class PostboardModule(object):
    """Represents a postboarding module"""

    def __init__(self, path_module, path_data_root):
        self.path_obj = path_module
        self.path_data_root = path_data_root
        self.path_data = self.path_data_root / self.path_obj.name

        prefix_match = re.match(
            r'Post\d{3}',
            self.path_obj.name,
            re.IGNORECASE,
            )

        self.true_module = self.path_obj.is_dir() and prefix_match

        self.abbrevition = prefix_match.group(0).lower() if self.true_module else None

    def make_data_dir(self):
        """Make the module's data dir if appropraite"""
        assert self.true_module, 'Not a true module.'
        try:
            self.path_data.mkdir()
        except FileExistsError:
            pass

    def codegen_sas_macro_variable(self):
        """Generate SAS code that will create an apporpraite macro variable"""
        assert self.true_module, 'Not a true module.'

        return r'%let {} = {}{};'.format(
            self.abbrevition,
            self.path_data,
            os.sep,
            )

    def __repr__(self):
        return '\n'.join([
            '',
            'Path is {}'.format(self.path_obj),
            'Abbreviation is {}'.format(self.abbrevition),
            ])



if __name__ == '__main__':
    import sys
    sys.path.append(os.path.join(os.environ['USERPROFILE'], 'HealthBI_LocalData'))
    import healthbi_env

    PATH_PROJECT_DATA = Path(healthbi_env.META['path_project_data']) / 'postboarding'
    try:
        PATH_PROJECT_DATA.mkdir()
    except FileExistsError:
        pass

    PATH_CURRENT = get_path_current()

    PATH_SAS_SETUP = PATH_PROJECT_DATA / 'postboarding_libraries.sas'


    print('BEGINNING GENERATION OF {}\n\n'.format(PATH_SAS_SETUP))
    with PATH_SAS_SETUP.open('w') as fh_codegen:

        fh_codegen.write('/*Code generation requested by {} on {}*/\n\n'.format(
            os.environ['UserName'],
            datetime.datetime.now()
            ))

        print('BEGINNING SCAN OF {}\n\n'.format(PATH_CURRENT))
        for path_ in PATH_CURRENT.iterdir():
            mod_ = PostboardModule(path_, PATH_PROJECT_DATA)
            print(mod_)
            if mod_.true_module:
                mod_.make_data_dir()
                fh_codegen.write('\n{}\n'.format(mod_.codegen_sas_macro_variable()))

    print('\n\nFINISHED GENERATION OF {}\n\n'.format(PATH_SAS_SETUP))
