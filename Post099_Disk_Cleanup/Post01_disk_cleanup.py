"""
### CODE OWNERS: Michael Menser

### OBJECTIVE:
  Clean up the disks used by the process.

### DEVELOPER NOTES:
  This program imports 999_Disk_Cleanup from the HealthBI branch in order to clean up the disks.
"""

import os
import sys
sys.path.append(os.path.join(os.environ['USERPROFILE'], 'HealthBI_LocalData'))
import healthbi_env

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================

if __name__ == '__main__':
    from Prod01_disk_cleanup import dir_cleanup
    dir_cleanup(healthbi_env.META["path_project_local"])
