/*
### CODE OWNERS: Michael Menser, Anna Chen

### OBJECTIVE:
	Calculate the number of members opting out of data sharing (given we are given an exclusion file).

### DEVELOPER NOTES:
	None
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

/*Library*/
libname post008 "&post008." access = readonly;
libname post012 "&post012.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*First assert that we have an data opt-out exclusion file before we import it and count the opt-outs.*/

%GetFileNamesFromDir(
	Directory = &path_project_received_ref.
	,Output = exclusion_file
	,KeepStrings = BNEXC
	)

%AssertDataSetPopulated(
	DataSetName = exclusion_file
	,ReturnMessage = "There is no exclusion file detected, aborting program"
	,FailAction = EndActiveSASSession
	)

/*Import the exclusion file.*/

proc sql noprint;
	select filename
	into :name_excl_file
	from exclusion_file;
quit;

filename Bene_map "%GetParentFolder(0)Bene_Excl.map";
filename Bene_Exc "&Path_Project_Received_Ref.&name_excl_file.";
libname Bene_Exc xmlv2 xmltype=xmlmap xmlmap=Bene_map;

data bene_exclusion (keep = HICN BeneExcReason);
	set Bene_Exc.bene_exclusion (rename = (BeneExcReason = BeneExcReason_pre));
	format BeneExcReason $64.;
		
		if BeneExcReason_pre eq "BD" then BeneExcReason = "Beneficiary Declined";
			else if BeneExcReason_pre eq "EC" then BeneExcReason = "Excluded by CMS";
			else if BeneExcReason_pre eq "PL" then BeneExcReason = "Participant List Change";
			else BeneExcReason = BeneExcReason_pre;

run;

data Bene_Control;
	set Bene_Exc.Bene_Control;
run;

/*Check record count for the bene exclusion file against the control total.*/

proc sql noprint;
		select 
			RecordCount
			format= 8.
			into: Control_RecordCount
		from
			Bene_control
		;
	quit;

%put &Control_RecordCount.;

%assertthat(%GetRecordCount(bene_exclusion), eq, &Control_RecordCount.,ReturnMessage=Provider row counts do not match.);

/*Now calculate the metric.*/

proc sql;
	create table pre_opt_out_metric as
	select
		"&name_client." as name_client
		"Basic" as metric_category
		,memcnt.time_period as time_period
		,"All" as elig_status_1
		,%GetRecordCount(bene_exclusion) as opt_out_count

	from post008.memcnt as memcnt

	group by
		memcnt.time_period
		,memcnt.elig_status_1
	;
quit;

/*Munge to target formats*/

proc transpose data=pre_opt_out_metric
		out=opt_out_metric_transpose(rename=(COL1 = metric_value))
		name=metric_id
		label=metric_name;
	by name_client time_period metric_category elig_status_1;
run;

data post012.metrics_optoutcount;
	format &metrics_key_value_cgfrmt.;
	set opt_out_metric_transpose;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%LabelDataSet(post012.metrics_optoutcount);

%put return_code = &syscc.; 
