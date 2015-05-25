/*
### CODE OWNERS: Shea Parkes

### OBJECTIVE:
	Provide a framework to perform DRG case mix adjustments.

### DEVELOPER NOTES:
	Not part of production because it depends upon all ACOs' data being aggregated.
	For testing purposes, it case-mixes at the provider level.
	Can't directly do a multinomial due to complexity of optimization.
		Have to do a series of one-vs-rest and normalize results.
	Assume real reporting level will be credible enough there is no need for penalization.
		This would mean each reporting level should have results for each discharge status.
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname post025 "&post025." access=readonly;

%let reporting_level = prv_id_inpatient; /*For development purposes.*/
*%let reporting_level = name_client;


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/





/**** STAGE DATA FOR ANALYSIS ****/

proc sql;
	create table full_agg as
	select
		time_period
		,&reporting_level.
		,discharge_status_desc
		,catx('_'
			,drg_inpatient
			,drg_version_inpatient
			) as drg format=$16. length=16
		,sum(cnt_discharges_inpatient) as discharges_sum format=comma12.
	from Post025.Details_Inpatient
	group by
		time_period
		,&reporting_level.
		,discharge_status_desc
		,drg
	order by
		time_period
		,&reporting_level.
		,discharge_status_desc
		,drg
	;
quit;

proc sql;
	create table eda_reporting_level as
	select
		time_period
		,&reporting_level.
		,sum(discharges_sum) as discharges_sum format=comma12.
	from full_agg
	group by 
		time_period
		,&reporting_level.
	order by 
		time_period
		,discharges_sum desc
	;
	create table eda_discharge_status_desc as
	select
		time_period
		,discharge_status_desc
		,sum(discharges_sum) as discharges_sum format=comma12.
	from full_agg
	group by 
		time_period
		,discharge_status_desc
	order by 
		time_period
		,discharges_sum desc
	;
quit;

proc sql;
	create table agg_filter as
	select agg.*
	from full_agg as agg
	inner join eda_reporting_level as eda on
		agg.time_period eq eda.time_period
		and agg.&reporting_level. eq eda.&reporting_level.
	where 
		agg.discharges_sum gt 0
	order by
		agg.time_period
		,agg.&reporting_level.
		,agg.discharge_status_desc
		,agg.drg 
	;
quit;



/**** DEFINE FUNCTION TO FIT SINGLE MODEL ****/
%macro fit_one_status(
	name_dset_input
	,chosen_discharge_status
	,name_dset_output_means
	,name_dset_output_covparms
	);
	/*
	For development/testing purposes only:
		%let name_dset_input = agg_filter;
		%let chosen_discharge_status = Discharged to Home;
	*/
	data _munge_input;
		set &name_dset_input.;
		by time_period;

		format cnt_success comma12.;
		if upcase(discharge_status_desc) eq "%upcase(&chosen_discharge_status.)" then cnt_success = discharges_sum;
		else cnt_success = 0;
	run;

	
	ods output 
		SolutionR = _eff_random
		ParameterEstimates = _eff_fixed
		covparms = _single_covparms
		;
	proc glimmix data=_munge_input method=laplace;
		by time_period;
		class &reporting_level. drg;
		model cnt_success / discharges_sum = / solution;
		random drg &reporting_level. / solution;
	run;
	ods output close;

	proc sql;
		create table &name_dset_output_means. as
		select
			random.time_period
			,random.&reporting_level.
			,"&chosen_discharge_status." as discharge_status_desc format=$256. length=256
			,logistic(fixed.Estimate + random.Estimate) as mu format=percent12.3
		from _eff_random as random
		left join _eff_fixed as fixed on
			random.time_period eq fixed.time_period
		where
			upcase(fixed.effect) eq 'INTERCEPT'
			and upcase(random.effect) eq "%upcase(&reporting_level.)"
		;
	quit;

	data &name_dset_output_covparms.;
		format time_period;
		format discharge_status_desc $256.;
		set _single_covparms;
		discharge_status_desc = "&chosen_discharge_status.";
	run;

	proc sql;
		drop table _munge_input;
		drop table _eff_random;
		drop table _eff_fixed;
		drop table _single_covparms;
	quit;

%mend fit_one_status;

/* %fit_one_status(agg_filter,Discharged to Home,testing_ouput_means,testing_ouput_covparms) */



/**** FIT ALL THE MODELS ****/

%macro loop_statuses(name_dset_input,name_dset_output_means,name_dset_output_covparms);
	%if %sysfunc(exist(&name_dset_output_means.)) %then %do;
		proc sql;
			drop table &name_dset_output_means.;
		quit;
	%end;
	%if %sysfunc(exist(&name_dset_output_covparms.)) %then %do;
		proc sql;
			drop table &name_dset_output_covparms.;
		quit;
	%end;

	%local list_statuses;
	proc sql noprint;
		select distinct discharge_status_desc
		into :list_statuses separated by '~'
		from &name_dset_input.
		order by discharge_status_desc
		;
	quit;

	%let cnt_statuses = %eval(%sysfunc(countc(&list_statuses.,%str(~))) + 1);
	%do i_status = 1 %to &cnt_statuses.;
		%let current_status = %scan(&list_statuses.,&i_status.,%str(~));

		%put FITTING MODEL FOR DISCHARGE STATUS = &current_status.;

		%fit_one_status(&name_dset_input.,&current_status.,_means_&i_status.,_covparms_&i_status.)

		proc append base=&name_dset_output_means. data=_means_&i_status.;
		proc append base=&name_dset_output_covparms. data=_covparms_&i_status.;
		run;

		proc sql;
			drop table _means_&i_status.;
			drop table _covparms_&i_status.;
		quit;
	%end;

	proc sort data=&name_dset_output_means.; by time_period; run;
	proc sort data=&name_dset_output_covparms.; by time_period; run;

%mend loop_statuses;

%loop_statuses(agg_filter,means_sloppy,covparms_sloppy)




/**** RE-NORMALIZE THE RESULTS ****/
/*It would be best to normalize on the logistic scale, but there's no closed form calculation to accomplish that.*/

proc sql;
	create table mu_raw as
	select
		base.time_period
		,base.&reporting_level.
		,base.discharge_status_desc
		,agg.discharges_sum as report_level_raw_cnt
		,base.report_dischstatus_raw_cnt
		,coalesce(base.report_dischstatus_raw_cnt, 0) / agg.discharges_sum as mu_raw format=percent12.3
	from (
		select
			time_period
			,&reporting_level.
			,discharge_status_desc
			,sum(discharges_sum) as report_dischstatus_raw_cnt format=comma12.
		from agg_filter
		group by
			time_period
			,&reporting_level.
			,discharge_status_desc
		) as base
	left join eda_reporting_level as agg on
		base.time_period eq agg.time_period
		and base.&reporting_level. eq agg.&reporting_level.
	order by
		time_period
		,report_level_raw_cnt desc
		,discharge_status_desc
	;
quit;


proc sql;
	create table results_normalized as
	select
		slop.time_period
		,slop.&reporting_level.
		,sort_report.discharges_sum as report_level_raw_cnt
		,slop.discharge_status_desc
		,sort_disch.discharges_sum as discharge_status_desc_raw_cnt
		,coalesce(raw.report_dischstatus_raw_cnt, 0) as report_dischstatus_raw_cnt format=comma12.
		,agg.report_level_slop_total
		,coalesce(raw.mu_raw, 0) as mu_raw format=percent8.3
		,slop.mu as mu_slop
		,slop.mu / agg.report_level_slop_total as mu_normalized format=percent8.3
	from means_sloppy as slop
	left join (
		select
			time_period
			,&reporting_level.
			,sum(mu) as report_level_slop_total format=percent8.3
		from means_sloppy
		group by 
			time_period
			,&reporting_level.
		) as agg on
		slop.time_period eq agg.time_period
		and slop.&reporting_level. eq agg.&reporting_level.
	left join mu_raw as raw on
		slop.time_period eq raw.time_period
		and slop.&reporting_level. eq raw.&reporting_level.
		and slop.discharge_status_desc eq raw.discharge_status_desc
	left join eda_reporting_level as sort_report on
		slop.time_period eq sort_report.time_period
		and slop.&reporting_level. eq sort_report.&reporting_level.
	left join eda_discharge_status_desc as sort_disch on
		slop.time_period eq sort_disch.time_period
		and slop.discharge_status_desc eq sort_disch.discharge_status_desc
	order by 
		time_period
		,report_level_raw_cnt desc
		,&reporting_level.
		,discharge_status_desc_raw_cnt desc
		,discharge_status_desc
	;
quit;



/**** CHECK FOR AGGREGATE DISTORTION LEVELS ****/

proc sql;
	create table post_distort_check as
	select
		agg.*
		,cov.Estimate as cov_estimate
		,cov.Stderr	as cov_stderr
	from (
		select
			time_period
			,discharge_status_desc
			,discharge_status_desc_raw_cnt
			,sum(mu_raw*report_level_raw_cnt)/sum(report_level_raw_cnt) as mu_comp_raw format=percent12.3
			,sum(mu_slop*report_level_raw_cnt)/sum(report_level_raw_cnt) as mu_comp_slop format=percent12.3
			,sum(mu_normalized*report_level_raw_cnt)/sum(report_level_raw_cnt) as mu_comp_normalized format=percent12.3
		from results_normalized
		group by
			time_period
			,discharge_status_desc
			,discharge_status_desc_raw_cnt
	) as agg
	left join covparms_sloppy as cov on
		agg.time_period eq cov.time_period
		and agg.discharge_status_desc eq cov.discharge_status_desc
	where upcase(cov.CovParm) eq "%upcase(&reporting_level.)"
	order by
		agg.time_period
		,agg.discharge_status_desc_raw_cnt desc
		,agg.discharge_status_desc
	;
quit;



/* Example holistic model */
/*
	This is an example of reaching a solution in a single step.
	Unfortunately, even when utilizing some covariance estimates from above,
	the speed of optimization is likely too slow to be useful.
	Additionally, the parameter estimates are awkward to re-combine into
	discharge status proportions.
*/
/*
ods output ParameterEstimates=coefs_reoptimize;
proc glimmix data=agg_filter startglm inititer=42 order=internal maxopt=4;
	by time_period;
	class discharge_status_desc &reporting_level. drg;
	freq discharges_sum;
	model discharge_status_desc = &reporting_level. / link=glogit solution;
	random drg / group=discharge_status_desc;
	parms /  noiter parmsdata=covparms_sloppy;
run;
ods output close;
*/


%put return_code = &syscc.;
