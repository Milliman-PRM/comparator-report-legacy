"""
### CODE OWNERS: Aaron Burgess

### OBJECTIVE:
  Test rename files function

### DEVELOPER NOTES:
  <none>
"""

from collections import namedtuple

import pytest

from Supp03_output_rename import rename_files, IndyPyPath

@pytest.fixture
def file_group(tmpdir):
    """Create a temp file group for testing"""
    real_files_nt = namedtuple('real_files', ['unwanted_file1',
                                              'unwanted_file2',
                                              'wanted_file1',
                                              'wanted_file2'])
    expected_files_nt = namedtuple('expected_files', ['wanted_changed_file1',
                                                      'wanted_changed_file2',
                                                      'unwanted_changed_file1',
                                                      'unwanted_changed_file2'])
    tmpdir_string = str(tmpdir)
    unwanted_file1 = tmpdir.join('test_all.sas7bdat')
    unwanted_file1.write('tacos')
    unwanted_file2 = tmpdir.join('test_1.sqlite')
    unwanted_file2.write('nothing')
    wanted_file1 = tmpdir.join('test_example.sas7bdat')
    wanted_file1.write('hulkamania')
    wanted_file2 = tmpdir.join('test_example.sqlite')
    wanted_file2.write('42')
    wanted_changed_file1 = str(IndyPyPath(tmpdir_string) / 'test_example_2.sas7bdat')
    wanted_changed_file2 = str(IndyPyPath(tmpdir_string) / 'test_example_2.sqlite')
    unwanted_changed_file1 = str(IndyPyPath(tmpdir_string) / 'test_all_2.sas7bdat')
    unwanted_changed_file2 = str(IndyPyPath(tmpdir_string) / 'test_1_2.sqlite')
    real_files = real_files_nt(*list(map(str, [unwanted_file1, unwanted_file2,
                                               wanted_file1, wanted_file2])))
    expected_files = expected_files_nt(wanted_changed_file1, wanted_changed_file2,
                                       unwanted_changed_file1, unwanted_changed_file2)
    return real_files, expected_files


def test_rename_files(file_group, tmpdir):
    """Ensure unwanted files are ignored and wanted files are renamed"""
    real_files, expected_files = file_group
    rename_files(str(tmpdir), '2')
    path_one_check = IndyPyPath(expected_files.wanted_changed_file1).exists()
    path_two_check = IndyPyPath(expected_files.wanted_changed_file2).exists()
    unwanted_path_one = IndyPyPath(expected_files.unwanted_changed_file1).exists()
    unwanted_path_two = IndyPyPath(expected_files.unwanted_changed_file1).exists()
    assert path_one_check
    assert path_two_check
    assert not unwanted_path_one
    assert not unwanted_path_two
    with pytest.raises(ValueError):
        rename_files(str(tmpdir), 'taco')
