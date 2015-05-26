"""
### CODE OWNERS: Michael Menser

### OBJECTIVE:
  Clean up the disks used by the process.

### DEVELOPER NOTES:
  <none>
"""

import healthbi_env

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================

from Prod01_disk_cleanup import dir_cleanup
dir_cleanup(healthbi_env.META["path_project_local"])
