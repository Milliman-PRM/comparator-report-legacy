/*
### CODE OWNERS: Michael Menser, Shea Parkes

### OBJECTIVE:
	Calculate the percentage of members with claims.

### DEVELOPER NOTES:
	Likely to be quite a boring metric if the population comes from an ACO with claims based assignment (e.g. Medicare MSSP)

*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname post008 "&post008." access=readonly;
libname post010 "&post010."; 

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/



/*** Find members with claims ***/

%agg_claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Med_Rx=Med
	,Dimensions=member_id
	,Time_Slice=&list_time_period.
	,Where_Elig=%str(member.assignment_indicator eq "Y")
	/*No member limits applied because outputs are merged against official roster below.*/
	,Suffix_Output=member
	)

%macro conditional_rx;
	%if %upcase(&rx_claims_exist.) eq YES %then %do;
		%agg_claims(
			IncStart=&list_inc_start.
			,IncEnd=&list_inc_end.
			,PaidThru=&list_paid_thru.
			,Med_Rx=Rx
			,Dimensions=member_id
			,Time_Slice=&list_time_period.
			/*No member limits applied because outputs are merged against official roster below.*/
			,Suffix_Output=member
			);
	%end;
	%else %do;
		data agg_claims_rx_member;
			set _Null_;
			format
				member_id $40.
				time_slice $32.
				;
		run;
	%end;
%mend conditional_rx;

%conditional_rx;



/*Calculate % of members with claims.*/

proc sql noprint;
	create table claims_percentages as
	select
		members.time_period
		,members.elig_status_1
		,(sum(case when medical.member_id is null then 0 else 1 end)) / (count(members.member_id)) 
			as percent_members_w_claims_med label="Percentage of Members with Medical Claims"
		,(sum(case when rx.member_id is null then 0 else 1 end)) / (count(members.member_id))
			as percent_members_w_claims_rx label="Percentage of Members with Rx Claims"
		,(sum(case when (medical.member_id is null AND rx.member_id is null) then 0 else 1 end)) / (count(members.member_id))
			as percent_members_w_claims_any label="Percentage of Members with Any Claims"

	from Post008.members as members 
	left join agg_claims_med_member as medical
		on members.member_id = medical.member_id and
		   members.time_period = medical.time_slice
	left join agg_claims_rx_member as rx
		on members.member_id = rx.member_id and
		   members.time_period = rx.time_slice
	group by
		members.time_period
		,members.elig_status_1
	order by
		members.time_period
		,members.elig_status_1
	;
quit;
 

proc transpose data = claims_percentages
	out = claims_percentages_long (rename = (col1 = metric_value))
	name = metric_id
	label = metric_name
	;
	by time_period elig_status_1;
run;

proc sql noprint;
	select round(max(metric_value),0.0001)
	into :max_pct_with_claims trimmed
	from claims_percentages_long
	;
quit;
%put &=max_pct_with_claims.;
%AssertThat(&max_pct_with_claims.,le,1,ReturnMessage=An inprobable percentage of members were determined to have claims.)

data post010.metrics_claims_percentages;
	format &metrics_key_value_cgfrmt.;
	set claims_percentages_long;
	by time_period elig_status_1;
	&assign_name_client.;
	metric_category = "Basic";
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%LabelDataSet(post010.metrics_claims_percentages)

%put System Return Code = &syscc.;





