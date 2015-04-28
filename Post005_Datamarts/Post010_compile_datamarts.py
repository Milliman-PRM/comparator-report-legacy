"""
### CODE OWNERS: Kyle Baird

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
    path_template_source = Path(healthbi_env.META["path_onboarding_code"]) / "Post005_Datamarts"
    # path_template_source = Path(r"C:\Users\Kyle.Baird\repos\Comparator_Report\Post005_Datamarts")
    path_dir_codegen_output = Path(healthbi_env.META[2, 'out'])
    list_template_names = [
        path_.name for path_ in path_template_source.iterdir() if path_.is_dir()
        ]

    # Make a local copy of this reference file because the DataMart class
    # requires it to be next to the source templates
    name_reference_file = "Ref01_Data_Types.csv"
    path_local_ref = path_template_source / "Ref01_Data_Types.csv"
    shutil.copyfile(
        str(Path(healthbi_env.META[2, 'code']) / name_reference_file),
        str(path_local_ref),
        )

    datamart_recursive = DataMart(
        path_templates=healthbi_env.META[2, 'code'],
        template_name="_Recursive_Template",
        )

    for name_template in list_template_names:
        # pylint: disable=anomalous-backslash-in-string
        sas_infile_path_string = "&path_onboarding_code.\Post005_Datamarts\\" + name_template

        print("Validating and code generating for template: {}".format(name_template))

        # Make a throw away datamart object so we can utilize the embedded validation
        # pylint: disable=unused-variable
        datamart_validate = DataMart(
            path_templates=str(path_template_source),
            template_name=name_template,
            )

        datamart_recursive.generate_sas_infiles(
            filepath_out=str(
                path_dir_codegen_output / "Template_Import_{}.sas".format(name_template)
                ),
            path_in=sas_infile_path_string,
            format_source_filename="{}.csv",
            table_name_replace=name_template,
            )

        path_local_ref.unlink()


if __name__ == '__main__':
    main()
