"""
### CODE OWNERS: Kyle Baird, Shea Parkes

### OBJECTIVE:
  Compile and do the code generation needed to utilize PRM data mart tool chain.

### DEVELOPER NOTES:
  Requires a standard PRM project to be set up and available
"""
import sys
import os
sys.path.append(os.path.join(os.environ['USERPROFILE'],
                             'HealthBI_LocalData'))
import healthbi_env
import shutil

from prod01_datamarts import DataMart
from pathlib import Path

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================




def main():
    """
        Run the main procedure. Creates and generates data marts for each
        provided data mart.
    """
    path_template_source = Path(os.path.realpath(__file__)).parent
    # path_template_source = Path(r"C:\Users\Kyle.Baird\repos\Comparator_Report\Post005_Datamarts")
    path_dir_codegen_output = Path(healthbi_env.META[2, 'out'])
    list_template_names = [
        path_.name.lower() for path_ in path_template_source.iterdir() if path_.is_dir()
        ]

    # Make a local copy of this reference file because the DataMart class
    # requires it to be next to the source templates
    list_reference_files = ["Ref01_Data_Types.csv", "Ref02_sqlite_import_header.sql"]
    for name in list_reference_files:
        shutil.copyfile(
            str(Path(healthbi_env.META[2, 'code']) / name),
            str(path_template_source / name),
            )

    datamart_recursive = DataMart(
        path_templates=healthbi_env.META[2, 'code'],
        template_name="_Recursive_Template",
        )

    for name_template in list_template_names:
        sas_infile_path_string = "&path_onboarding_code.\\{}\\{}".format(
            path_template_source.stem,
            name_template,
            )

        print("Validating and code generating for template: {}".format(name_template))

        i_datamart = DataMart(
            path_templates=str(path_template_source),
            template_name=name_template,
            )
        i_datamart.generate_sqlite_cli_import(
            filepath_out=str(
                path_dir_codegen_output / "{}.sql".format(name_template)
                )
            )

        datamart_recursive.generate_sas_infiles(
            filepath_out=str(
                path_dir_codegen_output / "Template_Import_{}.sas".format(name_template)
                ),
            path_in=sas_infile_path_string,
            format_source_filename="{}.csv",
            table_name_replace=name_template,
            )

    for name in list_reference_files:
        i_path = path_template_source / name
        i_path.unlink()


if __name__ == '__main__':
    main()
