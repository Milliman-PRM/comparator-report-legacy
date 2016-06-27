#Release Notes

## v6.0.0

### Client Visible Changes
 - Added member level reporting for CaroMont for the following metrics:
  - Preventable ED
  - Ambulatory Sensitive Admissions for Heart Failure
  - Part B Drug Expense and Utilization (non-chemo)
 
###  Logic Changes
 - *none* 

### Lower Level Changes
 - Removed reference to retired ```prm_parser```
 - Updated report split program to call postboarding libraries after assignment


## v5.2.0

### Client Visible Changes (e.g. Updates to the Comparator Report Datamart)
- Added readmission and cancer denominator counts
- Added a claims probability distribution to the output datamart
- Added an office administered drug summary to the output datamart
- Added a count of members without runout at the end of 2015 (applicable to the 201603 run only)

### Logic Changes
- *none*

### Lower Level Changes
- *none*

## v5.1.2
  - Munge the `sys.path` in disk cleanup because the new python parser no longer does so for you. This allows functions to be imported from the main analytics-pipeline `disk_cleanup` script

## v5.1.1
  - Re-instated the `Path()` call in Wrap-Up so the resulting object would `Path` object as expected by the program

## v5.1.0

### Client Visible Changes (e.g. Updates to the Comparator Report Datamart)
- *none*

### Logic Changes
- Updated Pioneer logic to create client member time based on the presence of claims in a given year

### Lower Level Changes
- Derive the most recent Beneficiary Exclusion file
- Fixed the market split naming code to only append the current market name
- Update to new python parser


## v5.0.0

#### Client Visible Changes (e.g. Updates to the Comparator Report Datamart)
- *none*

#### Logic Changes
- Use component MARA risk scores (this will not impact NYP)

#### Lower Level Changes
- Updated postboarding datamart creation script to be compatible with analytics-pipeline v5.11
