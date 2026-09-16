# jwellplate — Well Plate Maps for jamovi

A [jamovi](https://www.jamovi.org) module that draws coloured plate maps
(6 / 12 / 24 / 96 / 384 / 1536 wells) from plate-based experimental data,
similar in spirit to the Python
[`well_plate`](https://github.com/zindy/well_plate) module.

It handles both **numeric** data (continuous colour scale + colour bar)
and **categorical** data (discrete legend), and accepts either a single
"Well ID" column (`A1`, `A01`, ...) or separate Row and Column columns.

<img width="1650" height="1334" alt="jwellplate example plot" src="https://github.com/user-attachments/assets/06adcaf8-1dfe-48f1-9589-7730f2aaf3aa" />

## Contents

- [Installation](#installation)
- [Usage](#usage)
  - [Preparing your data](#preparing-your-data)
  - [Running the analysis](#running-the-analysis)
  - [Options](#options)
- [Development](#development)
- [License](#license)

## Installation

The recommended way to install jwellplate is from the jamovi library:
in jamovi, click the **"+"** icon in the top-right corner, open the
**jamovi library**, and search for "Well Plate Maps".

To try a development build before it's published to the library, you
can side-load it instead:

1. Build the module (see [Development](#development) below) to produce
   a `jwellplate.jmo` file.
2. In jamovi, open the jamovi library ("+" icon, top-right), go to the
   **Side-load** tab, and select the `.jmo` file.

A side-loaded `.jmo` only works on the OS/architecture/jamovi series it
was built on — see [Development](#development) for details.

## Usage

The analysis is called **Well Plate Map**, and lives under
**Modules → jwellplate** in the jamovi ribbon once the module is loaded.

### Preparing your data

Each row in your dataset should represent one well. You need **one** of
the following two ways to identify each well, plus a value to plot:

- **A single Well ID column**, which can hold either:
  - well-name strings such as `A1`, `A01`, `B12`, `H12`, etc. — leading
    zeros in the column number are optional and handled automatically
    (`A1` and `A01` are treated as the same well); or
  - plain 1-based well numbers, e.g. `1`, `2`, ... `96` for a 96-well
    plate. Wells are numbered row-major from the top-left well (`1`
    is `A1`, `nCols` is the last well of row A, `nCols + 1` is `B1`,
    and so on).
- **Separate Row and Column columns**, e.g. a Row column containing `A`,
  `B`, `C`, ... and a numeric Column column containing `1`, `2`, `3`, ...

Do not supply both a Well ID and a Row/Column pair — the analysis will
ask you to pick one.

Rows beyond `Z` are labelled `AA`, `AB`, ... as needed for 384- and
1536-well plates, matching the convention used by the Python
`well_plate` module.

The **Value** column is what gets drawn in each well:

- If it's numeric, wells are coloured on a continuous scale with a
  colour bar.
- If it contains text/category labels, wells are coloured with a
  discrete legend instead.

  jamovi sometimes auto-classifies whole-number columns as *Nominal*.
  jwellplate looks at the underlying values rather than jamovi's
  classification, so a column of numbers is still treated as numeric
  (continuous scale) even if jamovi labelled it Nominal — you don't
  need to manually change the variable type first.

Wells that aren't present in your data (or have a missing Value) are
left blank on the plate; see the **Cross out missing wells** option
below to mark them explicitly.

If a well ID appears more than once in your data, the last non-missing
value for that well is used. If none of your Well ID / Row+Column values
can be matched to a well at all, the analysis stops with an error rather
than silently drawing a blank plate.

### Running the analysis

1. Load your dataset and select **Modules → jwellplate → Well Plate Map**.
2. Assign either **Well ID**, or both **Row** and **Column**, to identify
   each well.
3. Assign the column you want to visualise to **Value**.
4. Adjust plate size, well shape, and colours under **Plate options** as
   needed.

### Options

| Option | Description |
| --- | --- |
| **Well ID** | A single variable holding well identifiers such as `A1` or `A01`. Use instead of Row/Column. |
| **Row** | A variable holding the row of each well (e.g. `A`, `B`, ...). Use instead of Well ID, together with Column. |
| **Column** | A variable holding the column number of each well (e.g. `1`, `2`, ...). Use instead of Well ID, together with Row. |
| **Value** | The variable to display in each well. Numeric values get a continuous colour scale + colour bar; categorical values get a discrete legend. |
| **Plate size** | Number of wells on the plate: 6, 12, 24, 96 (default), 384, or 1536. |
| **Well shape** | `Circle` (default) or `Square`. |
| **Colour scheme** | Colour scale for numeric data: Viridis (default), Magma, Plasma, Cividis, Reds, or Blues. Ignored for categorical data, which uses a discrete legend instead. |
| **Show colour bar / legend** | Toggle the colour bar (numeric data) or legend (categorical data). Default: on. |
| **Cross out missing wells** | Draw a red cross over wells with no data. Default: off. |
| **Draw plate border** | Draw a border around the whole plate. Default: on. |
| **Well size** | Size of each well relative to the grid spacing, from 0.1 to 1. Default: 0.85. |

## Development

jwellplate is a standard jamovi R module, built with
[`jmvtools`](https://github.com/jamovi/jmvtools):

```r
# from the module's root directory
jmvtools::install()
```

This produces a `jwellplate.jmo` file, which can be side-loaded into
jamovi for testing (see [Installation](#installation)).

### Continuous integration

Every push and pull request against `main` triggers `R CMD check` via
GitHub Actions — see [build.yml](.github/workflows/build.yml).

A tagged push additionally triggers a build of the `.jmo` file. The tag
version is picked up automatically from the [DESCRIPTION](DESCRIPTION)
file:

```
VERSION=$(grep "^Version:" DESCRIPTION | sed 's/Version: *//' | tr -d '[:space:]')
git tag -a "v$VERSION" -m "Release version $VERSION"
git push origin "v$VERSION"
```

After a release, bump the version number in `DESCRIPTION` (and
`jamovi/0000.yaml`) before starting the next round of development.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE)
file for details.

**Transparency notice regarding AI generation:** This extension was
conceptually architected by a human, but the boilerplate syntax and
specific script implementations were heavily assisted by generative AI
(Claude). Because AI-generated code currently resides in a legal grey
area regarding human authorship, the MIT license applied here strictly
covers the human arrangement, architectural choices, and integration.
The code is provided strictly "AS IS" with absolutely no warranties.