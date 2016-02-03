/*
### CODE OWNERS: Kyle Baird, Shea Parkes, Michael Menser

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

/*We have the data for the MARA risk scores by mr_line but the data for the CMS risk scores by mcrm_line.  Thus, we build a table by mr_line, add the MARA 
scores, merge on the MR to MCRM mapping, then add the CMS scores.*/


proc sql;
	create table MARA_riskscr_by_MRLine as
	select
		members.time_period
		,members.member_id
		,members.elig_status_1
		,members.memmos
		,members.riskscr_1
		,members.riskscr_1_type
		,ref_mr_line.mr_line
		,ref_mr_line.MARA_riskscr_component
		,case upcase(MARA_riskscr_component)
			when "RISKSCR_IP" then scores.riskscr_ip
			when "RISKSCR_ER" then scores.riskscr_er
			when "RISKSCR_OP" then scores.riskscr_op
			when "RISKSCR_PHY" then scores.riskscr_phy
			when "RISKSCR_RX" then scores.riskscr_rx
			else scores.riskscr_other
			end as factor_util_mara
		,case upcase(MARA_riskscr_component)
			when "RISKSCR_IP" then scores.riskscr_ip
			when "RISKSCR_ER" then scores.riskscr_er
			when "RISKSCR_OP" then scores.riskscr_op
			when "RISKSCR_PHY" then scores.riskscr_phy
			when "RISKSCR_RX" then scores.riskscr_rx
			else scores.riskscr_other
			end as factor_cost_mara
		,mcrm_mapping.mcrm_line
	from post008.members as members
	left join riskscr.mara_scores as scores on
		members.member_id = scores.member_id and members.time_period = scores.time_slice
	cross join M015_out.mr_line_info as ref_mr_line
	inner join Post008.Time_windows as time_periods on 
		time_periods.time_period = members.time_period and upcase(substr(scores.model_name,3,3)) = upcase(substr(time_periods.riskscr_period_type,1,3))
	inner join M015_out.link_mr_mcrm_line (where = (upcase(lob) eq "%upcase(&type_benchmark_hcg.)")) as mcrm_mapping on 
		ref_mr_line.mr_line = mcrm_mapping.mr_line
	order by
		members.time_period
		,members.member_id
		,mcrm_mapping.mcrm_line
	;
quit;

data MARA_riskscr_by_MCRMLine (drop = mr_line MARA_riskscr_component);
	set MARA_riskscr_by_MRLine;
	by time_period member_id mcrm_line;
	if first.mcrm_line;
run;

proc sql;
	create table risk_scores_service_member as
	select MARA.*
	       ,hcc_factors.factor_util as factor_util_hcc
		   ,hcc_factors.factor_cost as factor_cost_hcc
		   ,case upcase(MARA.riskscr_1_type)
		   		when "CMS HCC RISK SCORE" then hcc_factors.factor_util
				when "MARA RISK SCORE" then MARA.factor_util_mara
				else MARA.riskscr_1
				end as riskscr_1_util
			,case upcase(MARA.riskscr_1_type)
		   		when "CMS HCC RISK SCORE" then hcc_factors.factor_cost
				when "MARA RISK SCORE" then MARA.factor_cost_mara
				else MARA.riskscr_1
				end as riskscr_1_cost
	from MARA_riskscr_by_MCRMLine as MARA
	left join M015_out.mcrm_hcc_calibrations as hcc_factors on
		MARA.mcrm_line eq hcc_factors.mcrm_line
			and round(MARA.riskscr_1,0.01) between hcc_factors.hcc_range_bottom and hcc_factors.hcc_range_top
	order by
		MARA.time_period
		,MARA.member_id
		,MARA.mcrm_line
	;
quit;

/*Assert that no lines with 0 memmos have survived up to this point.*/
data service_member_0_memmos;
	set risk_scores_service_member;
	where memmos = 0;
run;

%AssertDataSetNotPopulated(service_member_0_memmos,"There are members with 0 member months in the data, and they should not be in the data.");

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
