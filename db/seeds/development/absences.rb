# frozen_string_literal: true

#  Copyright (c) 2006-2017, Puzzle ITC GmbH. This file is part of
#  PuzzleTime and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/puzzle/puzzletime.

if Settings.defaults.country == 'DE'
  # Recommended catalog for Germany, see doc/de-einsatz-leitfaden.md.
  # payed means "counts towards must hours" — sick leave beyond the six weeks
  # of Entgeltfortzahlung and Kindkrank stay payed, otherwise overtime would
  # run into the negative; actual remuneration is handled by payroll.
  # Elternzeit, Sabbatical and unpaid leave are deliberately not absences:
  # they are handled via a 0% employment.
  Absence.seed(
    :name,
    { name: 'Urlaub',
      payed: true,
      vacation: true },
    { name: 'Krankheit',
      payed: true },
    { name: 'Krankheit (Krankengeld)',
      payed: true },
    { name: 'Kindkrank',
      payed: true },
    { name: 'Mutterschutz',
      payed: true },
    { name: 'Sonderurlaub',
      payed: true },
    { name: 'Bildungsurlaub',
      payed: true },
    { name: 'Überstundenabbau',
      payed: false }
  )
else
  Absence.seed(
    :name,
    { name: 'Ferien',
      payed: true,
      vacation: true },
    { name: 'Krankheit',
      payed: true },
    { name: 'Militär',
      payed: true },
    { name: 'Heirat',
      payed: true },
    { name: 'Umzug',
      payed: true },
    { name: 'Überstundenkompensation',
      payed: false }
  )
end
