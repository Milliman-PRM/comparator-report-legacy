/*
### CODE OWNERS: Aaron Hoch 

### OBJECTIVE:
	Move all of the Comparator Report files into one central location (assemble the datamart). 

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

%MockLibrary(name_library_reference= M002_Cde
/*			,path_root_seed= &post005.\Comparator_Report*/
			,pollute_global= TRUE
			)
%put M002_cde = &M002_cde.;

%CreateFolder(&M002_cde.\&name_datamart_target.)

%CopyFile(File= Comparator_Report_Fields.csv
			,CurrentDir= %GetParentFolder(1)\Post005_Datamarts\Comparator_Report
			,ToDir= "&M002_cde.\&name_datamart_target."
			)

%CopyFile(File= Comparator_Report_Tables.csv
			,CurrentDir= %GetParentFolder(1)\Post005_Datamarts\Comparator_Report
			,ToDir= "&M002_cde.\&name_datamart_target."
			)

%MakeMetaFields(&name_datamart_target.
				,Post050.meta_field
				)
%LabelDataSet(post050.meta_field)

%MakeMetaProject(post050.meta_project)
%LabelDataSet(post050.meta_project)


proc sql noprint;
	select distinct
			name_table
		into :remaining_tables separated by " "				
		from Comparator_report_tables
		where upcase(name_table) ne "METRICS_KEY_VALUE"		/*This table is already in the Post050 library. So it does not need moved.*/
	;
quit;
%put remaining_tables = &remaining_tables.;


%GetFilenamesFromDir(
					Directory=&path_project_data.postboarding
					,Output=deliverable_files
					,Keepstrings=&remaining_tables.
					,subs=yes
					);

data parsed_filenames (drop=directory filename);
	set deliverable_files;
	files=scan(scan(filename,2,"\"),1,".");
	libraries=cats(directory,"\",scan(filename,1,"\"));
run;

proc sql noprint;
	select cats("'",libraries,"'")
	into :libs separated by ","
	from parsed_filenames
	;
quit;


libname Source (&libs.) access=readOnly;

proc datasets NOLIST;
	copy 
		in= source 
		out= post050 memtype= data
		;
	select &remaining_tables.;
quit;


	
	


%put System Return Code = &syscc.;
