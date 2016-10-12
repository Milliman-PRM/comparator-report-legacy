"""
### CODE OWNERS: Aaron Burgess

### OBJECTIVE:
  Write the results to the shared network location for delivery to the client

### DEVELOPER NOTES:
  <none>
"""
import typing

import prm.meta.project
from prm.meta.output_datamart import DataMart

PRM_META = prm.meta.project.parse_project_metadata()

NYP_PATH_TEMPLATES = PRM_META['path_onboarding_code']
PATH_TEMPLATES = PRM_META[2, 'code']
PATH_REF_DATATYPES = PATH_TEMPLATES / "Ref01_data_types.csv"

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================


def main():
    """Access Point"""
    NYP_DATAMART = DataMart(
                                path_templates=NYP_PATH_TEMPLATES,
                                template_name='Post005_Datamarts',
                                filepath_ref_datatypes=PATH_REF_DATATYPES
                            )

    DATAMART_RECURSIVE = DataMart(
        path_templates=PATH_TEMPLATES,
        template_name="_recursive_template",
        filepath_ref_datatypes=PATH_REF_DATATYPES
    )

    PATH_DIR_CODEGEN_OUTPUT = PRM_META[2, 'out']

    DATAMART_RECURSIVE.generate_sas_infiles(
        PATH_DIR_CODEGEN_OUTPUT / "Template_Import_{}.sas".format(NYP_DATAMART.template_name),
        "&M002_cde.\\{}".format(NYP_DATAMART.template_name),
        format_source_filename="{}.csv",
        table_name_replace=NYP_DATAMART.template_name
    )




