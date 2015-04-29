/*
### CODE OWNERS: Kyle Baird, Shea Parkes

### OBJECTIVE:
	Validate our internal templates against those contained in mainline HealthBI
	so we have some confidence out templates will work with PRM code gen tools

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&M002_cde.supp01_validation_functions.sas";

%let path_dir_template_root = %GetParentFolder(0);
%put path_dir_template_root = &path_dir_template_root.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




%GetFileNamesFromDir(
	&path_dir_template_root.
	,subdirs
	,types=dirs
	)

data _null_;
	set subdirs;
	call execute(
		cats(
			'%include "'
			,"&M002_Out.Template_Import_"
			,filename
			,'.sas" / source2;'
			)
		);
run;

%MockLibrary(validate)
%CreateLocalCache(
	source_lib=work
	,cache_lib=validate
	,dset_blacklist=subdirs
	)

data _null_;
	set subdirs;
	call execute(
		cats(
			'%nrstr(%ValidateAgainstTemplate(validate_libname=validate'
			,',validate_template=_recursive_template'
			,',_recursive_template_name_hook='
			,filename
			,'))'
			)
		);
run;

%put System Return Code = &syscc.;
