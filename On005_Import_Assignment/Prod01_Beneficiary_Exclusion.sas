/*
### CODE OWNERS: Jack Leemhuis, Anna Chen

### OBJECTIVE:
	Conditionally bring in member exclusion information.

### DEVELOPER NOTES:
	*/


options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

/* Libnames */

libname M017_Out "&M017_Out.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Find and assert file exists*/
%GetFileNamesfromDir(&Path_Project_Received_Ref.,ref_files,BNEXC)

%AssertThat(
	%GetRecordCount(ref_files)
	,gt
	,0
	,ReturnMessage=No member exclusion information
	,FailAction=endactivesassession
	)

/*Member exclusion information*/

proc sql noprint;
	select filename
	into :bnexc_file trimmed
	from ref_files
;
quit;

%put bnexc_file = &bnexc_file.;

filename Bene_map "%GetParentFolder(0)Bene_Excl.map";
filename Bene_Exc "&Path_Project_Received_Ref.&bnexc_file.";
libname Bene_Exc xmlv2 xmltype=xmlmap xmlmap=Bene_map;
 
data M017_Out.bene_exclusion (keep = HICN BeneExcReason);
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

*Check record count for the bene exclusion file against the control total;
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

%assertthat(%GetRecordCount(M017_Out.bene_exclusion), eq, &Control_RecordCount.,ReturnMessage=Provider row counts do not match.);

%put System Return Code = &syscc.;
