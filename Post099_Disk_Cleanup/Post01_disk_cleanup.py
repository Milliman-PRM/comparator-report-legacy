"""
### CODE OWNERS: Michael Menser, Shea Parkes

### OBJECTIVE:
  Clean up the disks used by the process.

### DEVELOPER NOTES:
  This program imports 999_Disk_Cleanup from the HealthBI branch in order to clean up the disks.
"""

import prm.meta.output_datamart
META = prm.meta.project.parse_project_metadata()
from Prod01_disk_cleanup import dir_cleanup

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================
if __name__ == '__main__':
    dir_cleanup(META["path_project_local"])
