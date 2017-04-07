"""
### CODE OWNERS: Kyle Baird, Shea Parkes, Aaron Burgess, Jason Altieri

### OBJECTIVE:
  Compile and do the code generation needed to utilize PRM data mart tool chain.

### DEVELOPER NOTES:
  Requires a standard PRM project to be set up and available
"""

import os
import shutil
from prm.meta.output_datamart import DataMart
from pathlib import Path

import prm.meta.project
META = prm.meta.project.parse_project_metadata()

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================


def main():
    """
        Run the main procedure. Creates and generates data marts for each
        provided data mart.
    """
    path_template_source = Path(os.path.realpath(__file__)).parent
    path_dir_codegen_output = META[2, 'out']
    list_template_names = [
        path_.name.lower() for path_ in path_template_source.iterdir() if path_.is_dir()
        ]

    mainline_template_names = {
        path_.name.lower()
        for path_ in META[2, 'code'].iterdir()
        if path_.is_dir()
        }

    datamart_recursive = DataMart(
        template_name="_Recursive_Template"
        )

    for name_template in list_template_names:
        assert name_template not in mainline_template_names, \
            '{} is already defined in mainline PRM'.format(name_template)

        sas_infile_path_string = str(path_template_source / name_template).lower()
        # Generalize the location; likely appropriate when running out of source control
        sas_infile_path_string = sas_infile_path_string.replace(
            os.environ['USERPROFILE'].lower(),
            '%SysGet(UserProfile)',
            )

        print("Validating and code generating for template: {}".format(name_template))

        i_datamart = DataMart(
            path_templates=path_template_source,
            template_name=name_template,
            )
        i_datamart.generate_sqlite_cli_import(
            filepath_out=
                path_dir_codegen_output / "{}.sql".format(name_template),
            )

        datamart_recursive.generate_sas_infiles(
            filepath_out=
                path_dir_codegen_output / "Template_Import_{}.sas".format(name_template)
                ,
            path_in=sas_infile_path_string,
            format_source_filename="{}.csv",
            table_name_replace=name_template,
            )



if __name__ == '__main__':
    main()
