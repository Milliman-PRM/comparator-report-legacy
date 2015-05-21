/*
### CODE OWNERS: Aaron Hoch 

### OBJECTIVE:
	Create some metadata tables to be included in the final database. 

### DEVELOPER NOTES:
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M002_Out.Template_Import_comparator_report.sas";
%include "&M013_Cde.Supp01_metadata.sas";

libname post050 "&post050.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

%MakeMetaFields(&name_datamart_target.
	,post050.ComparatorRpt00_meta_field
	)

%MakeMetaProject(standard_metadata)


%LabelDataSet(post050.ComparatorRpt00_meta_field)

%put System Return Code = &syscc.;

