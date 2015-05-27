/*
### CODE OWNERS: Kyle Baird

### OBJECTIVE:
	Export the data mart to a format suitable for consumption in something
	like Qlikview.

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M013_cde.Supp02_Export_Wrappers.sas";

libname post050 "&post050." access=readonly;

%let path_dir_local_temp = %MockDirectoryGetPath();
%put path_dir_local_temp = &path_dir_local_temp.;
%CreateFolder(&path_dir_local_temp.)

%let prefix_files_out = CompRpt;
%put prefix_files_out = &prefix_files_out.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




%WriteFlatFiles(
	name_datamart=&name_datamart_target.
	,libname_input=post050
	,path_temp_output=&path_dir_local_temp.
	)

%CreateSQLiteDatabase(
	name_datamart=&name_datamart_target.
	,path_input=&path_dir_local_temp.
	,path_output=&post050.
	,prefix=&prefix_files_out.
	)

/* TODO: Enable this once the QlikView report has been developed
%write_trigger(
	reportsplit=All
	,filename_qvw_template=comparator_report
	,prefix=&prefix_files_out.
	,clientcode=&profit_center_code.&client_initials.01
	,path_sqlite=&post050.
	,can_emit=False
	)
*/

%put System Return Code = &syscc.;
