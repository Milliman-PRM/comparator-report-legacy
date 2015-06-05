/*
### CODE OWNERS: Kyle Baird, Shea Parkes

### OBJECTIVE:
	Calibrate risk scores to service category to enhance the risk adjusted metrics
	by service category

### DEVELOPER NOTES:
	We are going to loosely assume that risk score types are chosen by elig_status_1
	values. Thus, there risk scores will be on roughly the same scale
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)Share01_Postboarding.sas" / source2;

/* Libnames */
libname M015_Out "&M015_Out." access=readonly;
libname post008 "&post008." access=readonly;
libname post009 "&post009.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




proc sql;
	create table risk_scores_service_member as
	select
		members.time_period
		,members.member_id
		,members.elig_status_1
		,members.memmos
		,members.riskscr_1_type
		,members.riskscr_1
		,ref_mcrm_line.mcrm_line
		/*Intentionally verbose to show selection logic*/
		,coalesce(hcc_factors.factor_util,members.riskscr_1) as factor_util_hcc
		,coalesce(hcc_factors.factor_cost,members.riskscr_1) as factor_cost_hcc
		,members.riskscr_1 as factor_util_mara
		,members.riskscr_1 as factor_cost_mara
		,case upcase(members.riskscr_1_type)
			when "CMS HCC RISK SCORE" then calculated factor_util_hcc
			when "MARA RISK SCORE" then members.riskscr_1 /*TODO: Populate with MARA service level risk scores when available*/
			else members.riskscr_1
			end as riskscr_1_util
		,case upcase(members.riskscr_1_type)
			when "CMS HCC RISK SCORE" then calculated factor_cost_hcc
			when "MARA RISK SCORE" then members.riskscr_1 /*TODO: Populate with MARA service level risk scores when available*/
			else members.riskscr_1
			end as riskscr_1_cost
	from post008.members as members
	cross join M015_out.ref_mcrm_line (where = (upcase(lob) eq "%upcase(&type_benchmark_hcg.)")) as ref_mcrm_line
	left join M015_out.mcrm_hcc_calibrations as hcc_factors on
		ref_mcrm_line.mcrm_line eq hcc_factors.mcrm_line
			and round(members.riskscr_1,0.01) between hcc_factors.hcc_range_bottom and hcc_factors.hcc_range_top
	order by
		members.time_period
		,members.member_id
		,ref_mcrm_line.mcrm_line
	;
quit;

proc means noprint nway missing data = risk_scores_service_member;
	class time_period elig_status_1 mcrm_line;
	var riskscr_1_util riskscr_1_cost;
	weight memmos;
	output out = post009.riskscr_service (drop = _:)
		mean =
			riskscr_1_util_avg
			riskscr_1_cost_avg
		sumwgt = memmos_sum
		;
run;
%LabelDataSet(post009.riskscr_service)

%put System Return Code = &syscc.;
