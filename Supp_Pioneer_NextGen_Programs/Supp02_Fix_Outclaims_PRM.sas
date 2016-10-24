/*
### CODE OWNERS: Jason Altieri, David Pierce

### OBJECTIVE:
  Hack the 073_outclaims_prm to deal with incorrect dollars/sign of days

### DEVELOPER NOTES:
	
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

/* Libnames */
libname M073_Out "&M073_Out.";

data M073_Out.outclaims_prm_orig;
	set M073_Out.outclaims_prm;
run;

proc summary nway missing data=M073_Out.outclaims_prm_orig (where = (upcase(substr(PRM_Line,1,1)) = "I" and FromDate ge mdy(1,1,2016)));
	class CaseAdmitID;
	var PRM_Admits PRM_Util MR_Cases_Admits MR_Units_Days PRM_Costs;
	output out=cases_rollup (drop = _:)sum=;
run;

data snf_claims (rename = (PRM_Admits = PRM_Admits_orig PRM_Util = PRM_Util_Orig PRM_Costs = PRM_Costs_Orig))
	 ip_claims (rename = (PRM_Admits = PRM_Admits_orig PRM_Util = PRM_Util_Orig PRM_Costs = PRM_Costs_Orig))
	 non_ip_claims;
	set M073_Out.outclaims_prm_orig;
	if upcase(PRM_Line) eq "I31" and FromDate ge mdy(2,1,2016) then do;
		output snf_claims;
	end;
	else if (upcase(substr(PRM_Line, 1, 1)) eq "I" and upcase(PRM_Line) ne "I31") and FromDate ge mdy(1,1,2016) then do;
		output ip_claims;
	end;
	else do;
		output non_ip_claims;
	end;
run;


proc sql;
	create table updated_ip_claims (drop = PRM_Admits_orig PRM_Costs_Orig PRM_Util_Orig) as
	select
		base.*
		,case when sign(case.PRM_Admits) ne sign(case.PRM_Util) and abs(case.PRM_Costs) lt 2 
				then 0 when sign(case.PRM_Admits) ne sign(case.PRM_Util)
				then sign(case.PRM_Admits) * abs(base.PRM_Util_orig) 
				else base.PRM_Util_orig end as PRM_Util
		,case when sign(case.PRM_Admits) ne sign(case.PRM_Util) and abs(case.PRM_Costs) lt 2 then 0
			else base.PRM_Costs_orig end as PRM_Costs
		,case when sign(case.PRM_Admits) ne sign(case.PRM_Util) and abs(case.PRM_Costs) lt 2 then 0
			else base.PRM_Admits_orig end as PRM_Admits
	from ip_claims as base
	left join cases_rollup as case on
		base.CaseAdmitID = case.CaseAdmitID
	;
quit;

proc sql;
	create table updated_snf_claims (drop = PRM_Admits_orig PRM_Costs_Orig PRM_Util_Orig) as
	select
		base.*
		,case when sign(case.PRM_Admits) ne sign(case.PRM_Util) and abs(case.PRM_Costs) lt 2 
				then 0 when sign(case.PRM_Admits) ne sign(case.PRM_Util)
				then sign(case.PRM_Admits) * abs(base.PRM_Util_orig) 
				else base.PRM_Util_orig end as PRM_Util
		,case when sign(case.PRM_Admits) ne sign(case.PRM_Util) and abs(case.PRM_Costs) lt 2 then 0
			else base.PRM_Costs_orig end as PRM_Costs
		,case when sign(case.PRM_Admits) ne sign(case.PRM_Util) and abs(case.PRM_Costs) lt 2 then 0
			else base.PRM_Admits_orig end as PRM_Admits
	from snf_claims as base
	left join cases_rollup as case on
		base.CaseAdmitID = case.CaseAdmitID
	;
quit;

data M073_Out.outclaims_prm;
	set non_ip_claims
		updated_ip_claims
		updated_snf_claims;
run;


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

%put System Return Code = &syscc.;
