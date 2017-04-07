/*
### CODE OWNERS: Aaron Hoch, Kyle Baird

### OBJECTIVE:
	Create some metadata tables to be included in the final database.

### DEVELOPER NOTES:
	Limitations on PRM functions require source datamarts definitions to
		be duplicated under a M002_cde location that is not part of PRM
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M013_Cde.Supp01_metadata.sas";

libname post050 "&post050.";

%let path_dir_datamart_def = %GetParentFolder(1)Post005_Datamarts\;
%put path_dir_datamart_def = &path_dir_datamart_def.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

%MakeMetaFields_custom(
	&name_datamart_target.
	,local_meta_field
	,path_dir_datamart_root=&path_dir_datamart_def.
	)

data Post050.meta_field;
	format &meta_field_cgfrmt.;
	set local_meta_field;
	&assign_name_client.;
	keep &meta_field_cgflds.;
run;
%LabelDataSet(post050.meta_field)

%MakeMetaProject(local_meta_project)

data Post050.meta_project;
	format &meta_project_cgfrmt.;
	set local_meta_project;
	&assign_name_client.;
	keep &meta_project_cgflds.;
run;
%LabelDataSet(post050.meta_project)


%put System Return Code = &syscc.;
