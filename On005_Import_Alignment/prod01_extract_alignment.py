"""
### CODE OWNERS: Shea Parkes

### OBJECTIVE:
  Extract contents of various excel files for later use

### DEVELOPER NOTES:
  Requires a standard PRM project to be set up and available
"""
import shutil
import re

from pathlib import Path
from openpyxl import load_workbook

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================


class AssignmentWorksheet(object):
    """A single sheet in an MSSP assignment Workbook"""

    def __init__(self, ws):
        self.ws_obj = ws
        self.key_cells = dict()
        self.date_start = None
        self.date_end = None

        for row in self.ws_obj.get_squared_range(0, 0, 24, 24):
            for cell in row:
                if cell.value is None:
                    continue
                if not isinstance(cell.value, str):
                    continue
                if cell.value.lower() == 'hicno':
                    self.key_cells['hicno'] = cell
                if re.search(r'\bparticipant tin\b', cell.value, re.I):
                    self.key_cells['tin'] = cell
                if re.search(r'\bnpi\b', cell.value, re.I):
                    self.key_cells['npi'] = cell

        if 'hicno' not in self.key_cells:
            self.intrinsic_value = 0
        elif len({cell.row for cell in self.key_cells.values()}) > 1:
            self.intrinsic_value = 0
        else:
            self.intrinsic_value = len(self.key_cells)


class AssignmentWorkbook(object):
    """An MSSP assignment workbook from CMS"""

    def __init__(self, wb_path):
        self.wb_path = wb_path
        self.wb_obj = load_workbook(
            str(wb_path),
            read_only=True,
            keep_vba=False,
            data_only=True,
            )
        self.worksheets = [AssignmentWorksheet(ws) for ws in self.wb_obj]
        self._max_intrinsic_value = max((
            ws.intrinsic_value
            for ws in self.worksheets
            ))
        self.key_worksheet = [
            ws
            for ws in self.worksheets
            if ws.intrinsic_value == self._max_intrinsic_value
            ][0]


def uncover_xlsx_files(path_sniffing):
    """Find potential assignment files that might be missing an 'xlsx' extension"""
    assert path_sniffing.is_dir(), '{} is not a directory'.format(str(path_sniffing))

    for file_ in path_sniffing.rglob('*'):
        if not file_.is_file():
            continue
        if file_.suffix.lower() == '.xlsx':
            continue
        if re.search(r'ACO\.[HQ]ASSGN\.D', file_.name, re.IGNORECASE):
            file_with_ext = file_.parent / (file_.name + '.xlsx')
            if file_with_ext.is_file():
                continue
            print('Duplicating {} with an "xlsx" extension'.format(file_))
            shutil.copy(str(file_), str(file_with_ext))


if __name__ == '__main__':
    root_path = Path(r"P:\PHI\FAL\3.SHA-FAL(NYP_Dev)\5-Support_Files\01-SHA_Data_Thru_201503_Demo\_From_Client\Scrappy_References\\")
    uncover_xlsx_files(root_path)
    for path_wb in root_path.rglob('*.xlsx'):
        print('\n' + path_wb.name)
        wb = AssignmentWorkbook(path_wb)
        print(wb.key_worksheet.ws_obj.title)
        print(wb.key_worksheet.key_cells)
