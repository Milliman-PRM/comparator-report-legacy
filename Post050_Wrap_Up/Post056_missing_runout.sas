/*
### CODE OWNERS: Jason Altieri

### OBJECTIVE:
	Output the number of members missing runout. This program can be deleted after the 201603 runs have been completed.

### DEVELOPER NOTES:
	<none>
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname M035_Out "&M035_Out." access=readonly;
libname post050 "&post050.";

%let NYMS_pre = K:\PHI\0273NYP\NewYorkMillimanShare\&project_id.\&deliverable_name.\;
%GetFileNamesfromDir(&NYMS_pre.,comp_report_folders,);

proc sort data=comp_report_folders out=comp_report_folders_sort;
	by directory descending filename;
run;

data comp_report_folders_sort_dist;
	set comp_report_folders_sort;
	by directory descending filename;

	if first.directory then output;
run;

proc sql noprint;
	select filename
	into :recent_comp_folder trimmed
	from comp_report_folders_sort_dist
	;
quit;
%put &=recent_comp_folder.;

libname NYMS "&NYMS_pre.&recent_comp_folder.\";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Output count of members missing runout to postboarding 050_Wrap_Up data directory*/

proc sql;
	create table assigned_elig_nov as
	select distinct
		member_id
	from M035_Out.Member_Time
	where cover_medical = "Y" and assignment_indicator = "Y" and elig_month = mdy(11,15,2015)
	;
quit;

proc sql;
	create table assigned_elig_dec as
	select distinct
		member_id
	from M035_Out.Member_Time
	where cover_medical = "Y" and assignment_indicator = "Y" and elig_month = mdy(12,15,2015)
	;
quit;

proc sql;
	create table NYMS.missing_runout as
	select
		count (distinct member_id) as missing_runout
	from (
		select 
			nov.member_id
			,case when dec.member_id is not null then 1 else 0 end as dec_flag
		from assigned_elig_nov as nov
		left join assigned_elig_dec as dec
			on nov.member_id = dec.member_id
		) as nest
	where dec_flag = 0
	;
quit;



%put System Return Code = &syscc.;
