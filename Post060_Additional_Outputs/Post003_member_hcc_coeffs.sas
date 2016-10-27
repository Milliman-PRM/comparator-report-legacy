/*
### CODE OWNERS: Jason Altieri, Aaron Burgess

### OBJECTIVE:
	Create a table of HCC coefficients that can be summed to a risk score.

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

/* Libnames */
libname HCC "&M090_cde.HCC\HCC Programs" access = readonly;
libname post008 "&post008." access = readonly;
libname post060 "&post060.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

data member_hcc_and_other_flags;
	set post008.member_hcc_flags;

	if (sex = '1' and ORIGDS = 1) then OriginallyDisabled_Male = 1;
	else OriginallyDisabled_Male = 0;

	if (sex = '2' and ORIGDS = 1) then OriginallyDisabled_Female = 1;
	else OriginallyDisabled_Female = 0;

	if (sex = '1' and MCAID = 1 and DISABL = 0) then MCAID_Male_Aged = 1;
	else MCAID_MALE_Aged = 0;

	if (sex = '2' and MCAID = 1 and DISABL = 0) then MCAID_Female_Aged = 1;
	else MCAID_Female_Aged = 0;

	if (sex = '1' and MCAID = 1 and DISABL = 1) then MCAID_Male_Disabled = 1;
	else MCAID_Male_Disabled = 0;

	if (sex = '2' and MCAID = 1 and DISABL = 1) then MCAID_Female_Disabled = 1;
	else MCAID_Female_Disabled = 0;

	if (DISABL = 1 and HCC6 = 1) then DISABLED_HCC6 = 1;
	else DISABLED_HCC6 = 0;

	if (DISABL = 1 and HCC46 = 1) then DISABLED_HCC46 = 1;
	else DISABLED_HCC46 = 0;

	if (DISABL = 1 and HCC34 = 1) then DISABLED_HCC34 = 1;
	else DISABLED_HCC34 = 0;

	if (DISABL = 1 and HCC54 = 1) then DISABLED_HCC54 = 1;
	else DISABLED_HCC54 = 0;

	if (DISABL = 1 and HCC55 = 1) then DISABLED_HCC55 = 1;
	else DISABLED_HCC55 = 0;

	if (DISABL = 1 and HCC110 = 1) then DISABLED_HCC110 = 1;
	else DISABLED_HCC110 = 0;

	if (DISABL = 1 and HCC176 = 1) then DISABLED_HCC176 = 1;
	else DISABLED_HCC176 = 0;

	if ((HCC19 = 1 or HCC18 = 1 or HCC17 = 1) and HCC85 = 1) then DIABETES_CHF = 1;
	else DIABETES_CHF = 0;

	if (HCC2 =1 and (HCC82 = 1 or HCC83 = 1 or HCC84 = 1)) then SEPSIS_CARD_RESP_FAIL = 1;
	else SEPSIS_CARD_RESP_FAIL = 0;

	if (HCC85 = 1 and (HCC110 = 1 or HCC111 = 1)) then CHF_COPD = 1;
	else CHF_COPD = 0;

	if ((HCC110 = 1 or HCC111 = 1) and (HCC82 = 1 or HCC83 = 1 or HCC84 = 1)) then COPD_CARD_RESP_FAIL = 1;
	else COPD_CARD_RESP_FAIL = 0;

	if (HCC85 = 1 and (HCC134 = 1 or HCC135 = 1 or HCC136 = 1 or HCC137 = 1)) then CHF_RENAL = 1;
	else CHF_RENAL = 0;

	if ((HCC8 = 1 or HCC9 = 1 or HCC10 = 1 or HCC11 = 1 or HCC12 = 1) and HCC47 = 1) then CANCER_IMMUNE = 1;
	else CANCER_IMMUNE = 0;

run;

proc sql noprint;
	select
		name
	into :transpose_cols separated by " "
	from dictionary.columns
	where upcase(libname) = "WORK" and upcase(memname) = "MEMBER_HCC_AND_OTHER_FLAGS" 
		and (upcase(name) not in ("HICNO", "DOB", "TIME_SLICE", "INCSTART", "INCEND", "PAIDTHRU", 
			"OREC", "SEX", "MCAID", "NEMCAID", "RISKSCR_MM", "SCORE_COMMUNITY", "SCORE_INSTITUTIONAL", 
			"SCORE_NEW_ENROLLEE", "SCORE_SNP_NEW_ENROLLEE", "AGEF", "ORIGDS", "DISABL"))
	;
quit;

%put &=transpose_cols.;

proc sort data=member_hcc_and_other_flags;
	by HICNO DOB TIME_SLICE OREC SEX MCAID NEMCAID ORIGDS DISABL AGEF RISKSCR_MM SCORE_COMMUNITY SCORE_NEW_ENROLLEE;
run;

proc transpose data=member_hcc_and_other_flags
	out=member_hcc_long (where=(coeff1 eq 1 and upcase(substr(_NAME_,1,2)) ne "CC"))
	prefix=coeff;
	by HICNO DOB TIME_SLICE OREC SEX MCAID NEMCAID ORIGDS DISABL AGEF RISKSCR_MM SCORE_COMMUNITY SCORE_NEW_ENROLLEE;
	var &transpose_cols.;
run;

proc transpose data=hcc.hcccoefn
	out=coeff_long (where = (upcase(substr(_NAME_,1,2)) in ("CE", "NE")));
run;

data CE_coeff;
	set coeff_long;
	where upcase(substr(_NAME_, 1, 2)) = "CE";

	new_name = substr(_NAME_,4);
run;

data NE_MCAID_ORIGDIS_coeff;
	set coeff_long;
	where upcase(substr(_NAME_, 1, 16)) = "NE_MCAID_ORIGDIS";

	new_name = substr(_NAME_, 18);
run;

data NE_MCAID_NORIGDIS_coeff;
	set coeff_long;
	where upcase(substr(_NAME_, 1, 17)) = "NE_MCAID_NORIGDIS";

	new_name = substr(_NAME_, 19);
run;

data NE_NMCAID_ORIGDIS_coeff;
	set coeff_long;
	where upcase(substr(_NAME_, 1, 17)) = "NE_NMCAID_ORIGDIS";

	new_name = substr(_NAME_, 19);
;

data NE_NMCAID_NORIGDIS_coeff;
	set coeff_long;
	where upcase(substr(_NAME_, 1, 18)) = "NE_NMCAID_NORIGDIS";

	new_name = substr(_NAME_, 20);
run;

proc sql;
	create table post060.member_riskscr_coeff as
	select
		mem.hicno
		,mem.time_slice
		,case when (upcase(substr(mem._NAME_,1,2)) = "NE" and mem.origds = 0 and mem.mcaid = 1) then cats('NORIGDIS_MCAID_', mem._NAME_)
			when (upcase(substr(mem._NAME_,1,2)) = "NE" and mem.origds = 1 and mem.mcaid = 0) then cats('ORIGDIS_NMCAID_', mem._NAME_)
			when (upcase(substr(mem._NAME_,1,2)) = "NE" and mem.origds = 1 and mem.mcaid = 1) then cats('ORIGDIS_MCAID_', mem._NAME_)
			when (upcase(substr(mem._NAME_,1,2)) = "NE" and mem.origds = 0 and mem.mcaid = 0) then cats('NORIGDIS_NMCAID_', mem._NAME_) 
			else mem._NAME_
		end as variable label=''
		,mem._LABEL_ as description label=''
		,comm.col1 as comm_coeff
		,case when (mem.origds = 0 and mem.mcaid = 0) then nenmno.col1
			when (mem.origds = 0 and mem.mcaid = 1) then nemno.col1
			when (mem.origds = 1 and mem.mcaid = 0) then nenmo.col1
			else nemo.col1 end as ne_coeff
	from member_hcc_long as mem
	left join CE_coeff as comm
		on mem._NAME_ = comm.new_name
	left join NE_NMCAID_NORIGDIS_coeff as nenmno
		on mem._NAME_ = nenmno.new_name
	left join NE_NMCAID_ORIGDIS_coeff as nenmo
		on mem._NAME_ = nenmo.new_name
	left join NE_MCAID_NORIGDIS_coeff as nemno
		on mem._NAME_ = nemno.new_name
	left join NE_MCAID_ORIGDIS_coeff as nemo
		on mem._NAME_ = nemo.new_name
	;
quit;

proc sql;
	create table post060.member_riskscores as
	select distinct
		hicno
		,time_slice
		,riskscr_mm
		,score_community
		,score_new_enrollee
	from member_hcc_long
	;
quit;


/*TEST RECON*/
proc summary nway missing data=post060.member_riskscr_coeff;
	class hicno time_slice;
	var ne_coeff comm_coeff;
	output out=riskscr_recon (drop = _:)sum=;
run;

proc sql;
	create table riskscore_compare as
	select
		coeff.*
		,scr.riskscr_mm
		,scr.score_community
		,scr.score_new_enrollee
	from riskscr_recon as coeff
	left join post060.member_riskscores as scr
		on coeff.hicno = scr.hicno and coeff.time_slice = scr.time_slice
	;
quit;

data recon (where = (diff_ne ne 0 or diff_comm ne 0));
	set riskscore_compare;

	if SCORE_NEW_ENROLLEE ne 0.01 then diff_ne = round(sum(ne_coeff, -score_new_enrollee),.001);
	else diff_ne = 0;
	diff_comm = round(sum(comm_coeff, -score_community),.001);
run;

%AssertDatasetNotPopulated(recon);

%put System Return Code = &syscc.;
