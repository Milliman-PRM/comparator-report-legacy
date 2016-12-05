"""
### CODE OWNERS:  Aaron Burgess, Jason Altieri
### OBJECTIVE:
  The exclusion files sent by CMS are known to be corrupt xls files that are not recoverable into the
  appropriate state.  This script will extract the data from the file stream itself.
### DEVELOPER NOTES:
  This will need amending in the event of correct xls deliveries
"""
import logging
import typing
import re
import csv

import prm.meta.project

from indypy.file_utils import IndyPyPath

LOGGER = logging.getLogger(__name__)
PRM_META = prm.meta.project.parse_project_metadata()

_REFERENCE_DATA = PRM_META['path_project_received_ref']
_FILTER_STATEMENTS = ["Transition to Medicare Advantage (MA)", "Medicare as Secondary Payer",
                      "Date of Death prior to start of Performance Year",
                      "Enrollment during the MA Open Enrollment Period (OEP)", "Loss of Part A or B",
                      "Beneficiary aligned to another Program"]

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================


def _chunk_data(file: IndyPyPath) -> typing.List[str]:
    """
    Takes incoming file and chunks actual data into list of data string

    Args:
        file: IndyPyPath

    Returns:
        List of strings where even indexes feature attribution and odd indexes contain hicno
    """
    with file.open(encoding='iso-8859-1') as infile:
        data = infile.read()
    pre_data_split = data.split('alignment.')[1]
    final_data = pre_data_split[:pre_data_split.find('HICNO') + len('HICNO')].strip('\n%\x00\x00')
    clean_data = re.sub(r'[\0\a\b\t\v\f\x1a\x01\x02\x03\x06\x04\x13\x11\x05\x07\x12\x10]+', ',', final_data)
    no_return_data = re.sub(r'\n', '', clean_data)
    return re.split(r'(\w\d{10}|\d{9}\w)', no_return_data)


def _write_new_data(output_file: IndyPyPath, data: typing.List[str]):
    """
    Serializes the extracted data to file

    Args:
        output_file: IndyPyPath object representing outfile
        data: Extracted data from corrupt xls

    """
    with output_file.open('w',
              newline='', errors='ignore') as outfile:
        current_filter = None
        writer = csv.writer(outfile)
        writer.writerow(['reason', 'hicno'])
        for count, line in enumerate(data):
            if count % 2 == 0:
                rows = []
                for filter in _FILTER_STATEMENTS:
                    if filter in line:
                        rows.append(filter)
                        current_filter = filter
                if not rows:
                    rows.append(current_filter)
            else:
                rows.append(line)
            if len(rows) == 1:
                continue
            writer.writerow(rows)


def main() -> int:
    """A function to enclose the execution of business logic."""
    LOGGER.info('About to do something stupid.')

    exclusion_files = [rfile for rfile in _REFERENCE_DATA.collect_files_regex(r'MNGREB\.RP')
                       if rfile.suffix != '.csv']
    LOGGER.info('Found %d exclusion files' % len(exclusion_files))

    for file in exclusion_files:
        LOGGER.info('Extracting data from %s' % str(file))
        data = _chunk_data(file)
        output_file = file.with_suffix('.csv')
        _write_new_data(output_file, data)
        LOGGER.info('Wrote new file: %s' % str(output_file))

    return 0


if __name__ == '__main__':
    # pylint: disable=wrong-import-position, wrong-import-order, ungrouped-imports
    import sys
    import prm.utils.logging_ext

    prm.utils.logging_ext.setup_logging_stdout_handler()

    RETURN_CODE = main()

    sys.exit(RETURN_CODE)