begin;
-- take a look to what we're up against.
select v, f, c, w, count(*) from (
    select array_length(voltage,1), array_length(frequency, 1),
       array_length(conductor_bundles, 1), array_length(subconductors, 1)
       from electrical_properties where power_type = 'l' and voltage is not null
) t (v,f,c,w) group by v,f,c,w order by count(*) desc;

/* THEORY

* Line parameters should be consistent and eventually simple.
* Meaning that each line parameter (voltage, frequency, cables, wires)
* should be repeated exactly N times, that each combination of
* voltage and frequency is distinct; and that the i-th element of each
* array represents a single power line (3-phase if AC and HV)

* The problem is of course, that lines are not tagged so consistently.
* We recognise and try to fix the following errors:

* - Missing value, categorised as Fully Missing Values and
    Partially Missing values
* - Value ratios; specifically the case of N*X voltage levels over X
    cables, where X is a multiple of 3
* - Conflicting values, whereby the combination of (voltage,
    frequency) is associated with conflicting values of (cables,
    wires). Included in this set are point inconsistencies (one of the
    values is different from a repeated number of other values).

* Each of these is to be handled differently.

* Fully missing values are filled in with default values. This is the
  purpose of the 'reference_parameters' table

* Partially missing values, where line which is constituted out of
  multiple lines, and some but not all of lines have (or lack) certain
  values, leading to an unequal number of repetitions. The fix is to
  extend these to the maximum number. However, initially, such
  values may be inconsistent.

* Value ratios, most commonly seen as a line that hat 220kV and 380kV
  voltage and a single entry of 6 cables. The most plausible
  explanation for such lines is that each 3-phase circuit has 3
  cables.

* Conflicting values are quite probably best handled by a majority
  'vote', tie-breaked either by random choice, or by largest- or
  smallest value.

*/





-- or this
select v, count(*) from (
    select unnest(voltage) from electrical_properties where power_type = 'l'
) t(v) group by v order by v desc;

commit;
