from __future__ import annotations

import shutil
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from explainctl_lib import typst_math  # noqa: E402


def fake_t2l(source: str) -> str:
    """t2l-shaped stub: `$x$` -> `$T(x)$`, `$$x$$` -> `$ T(x) $` where T
    strips backslashes and upper-cases, so converted output is tellable."""
    if source.startswith("$$") and source.endswith("$$"):
        return "$ %s $" % source[2:-2].replace("\\", "").upper()
    return "$%s$" % source[1:-1].replace("\\", "").upper()


class CountingRun:
    def __init__(self, run=fake_t2l):
        self.calls = []
        self.run = run

    def __call__(self, source):
        self.calls.append(source)
        return self.run(source)


class CollapseDigitsTest(unittest.TestCase):
    def test_spaced_literals_join(self):
        self.assertEqual(typst_math.collapse_digits("0 . 1 5 8 7 1"), "0.15871")
        self.assertEqual(typst_math.collapse_digits("5 0"), "50")
        self.assertEqual(typst_math.collapse_digits("x = 1 . 5 y"), "x = 1.5 y")

    def test_idempotent(self):
        once = typst_math.collapse_digits("0 . 1 5")
        self.assertEqual(typst_math.collapse_digits(once), once)

    def test_prose_words_untouched(self):
        self.assertEqual(typst_math.collapse_digits("a b c"), "a b c")


class ReplacePercentTest(unittest.TestCase):
    def test_bare_percent_becomes_sym(self):
        self.assertEqual(typst_math.replace_percent("5 0 %"), "5 0 #sym.percent")

    def test_text_regions_protected(self):
        self.assertEqual(
            typst_math.replace_percent('#text[50%] and "a%b" and %'),
            '#text[50%] and "a%b" and #sym.percent',
        )

    def test_idempotent(self):
        once = typst_math.replace_percent("50 %")
        self.assertEqual(typst_math.replace_percent(once), once)


class UnnestTextMathTest(unittest.TestCase):
    def _inner(self, latex):
        return latex.upper()

    def test_mixed_text_and_math(self):
        self.assertEqual(
            typst_math.unnest_text_math("#text[rate is $x$ high]", self._inner),
            '"rate is " X " high"',
        )

    def test_pure_math_unwraps(self):
        self.assertEqual(typst_math.unnest_text_math("#text[$x$]", self._inner), "X")

    def test_plain_text_untouched(self):
        self.assertEqual(
            typst_math.unnest_text_math("#text[prop\\_var]", self._inner),
            "#text[prop\\_var]",
        )

    def test_quotes_escaped(self):
        self.assertEqual(
            typst_math.unnest_text_math('#text[a "q" $x$]', self._inner),
            '"a \\"q\\" " X',
        )


class ConvertMarkdownTest(unittest.TestCase):
    DOC = (
        "# Title\n\n"
        "Inline $a+b$ here.\n\n"
        "```python\n"
        "print('$notmath$')\n"
        "```\n\n"
        "Code span `$alsonot$` stays.\n\n"
        "$$\n"
        "\\frac{x}{y}\n"
        "$$\n"
    )

    def test_code_protected_math_converted(self):
        run = CountingRun()
        out, warnings = typst_math.convert_markdown(self.DOC, run)
        self.assertEqual(warnings, [])
        self.assertIn("$A+B$", out)
        self.assertIn("$$\nFRAC{X}{Y}\n$$", out)
        self.assertIn("print('$notmath$')", out)
        self.assertIn("`$alsonot$`", out)
        self.assertEqual(len(run.calls), 2)

    def test_display_marker_stays_double_dollar(self):
        out, _ = typst_math.convert_markdown("$$x$$", CountingRun())
        self.assertEqual(out, "$$X$$")

    def test_escaped_dollar_not_a_delimiter(self):
        run = CountingRun()
        out, _ = typst_math.convert_markdown("costs \\$5 and \\$6 total", run)
        self.assertEqual(out, "costs \\$5 and \\$6 total")
        self.assertEqual(run.calls, [])

    def test_failed_segment_kept_verbatim_with_warning(self):
        def broken(_source):
            raise OSError("no t2l")

        out, warnings = typst_math.convert_markdown("keep $x$ here", broken)
        self.assertEqual(out, "keep $x$ here")
        self.assertEqual(len(warnings), 1)
        self.assertIn("no t2l", warnings[0].as_dict()["detail"])


class ConvertChangedTest(unittest.TestCase):
    def test_only_changed_regions_converted(self):
        before = "intro $old$ stays\n\nunchanged tail\n"
        after = "intro $old$ stays\n\nnew line with $fresh$\n\nunchanged tail\n"
        run = CountingRun()
        out, warnings = typst_math.convert_changed(before, after, run)
        self.assertEqual(warnings, [])
        self.assertIn("$old$", out)  # pre-existing math untouched
        self.assertIn("$FRESH$", out)
        self.assertEqual(run.calls, ["$fresh$"])

    def test_new_file_converts_everything(self):
        run = CountingRun()
        out, _ = typst_math.convert_changed(None, "$a$ and $$b$$", run)
        self.assertEqual(out, "$A$ and $$B$$")
        self.assertEqual(len(run.calls), 2)

    def test_no_change_no_conversion(self):
        run = CountingRun()
        text = "same $x$ doc\n"
        out, warnings = typst_math.convert_changed(text, text, run)
        self.assertEqual(out, text)
        self.assertEqual(warnings, [])
        self.assertEqual(run.calls, [])

    def test_replaced_math_line_converted(self):
        before = "head\n$1+1$\ntail\n"
        after = "head\n$2+2$\ntail\n"
        run = CountingRun()
        out, _ = typst_math.convert_changed(before, after, run)
        self.assertIn("$2+2$".upper().replace("2+2", "2+2"), out)
        self.assertEqual(run.calls, ["$2+2$"])


class PostprocessPipelineTest(unittest.TestCase):
    """The three pilot hazards, end to end through one segment."""

    def test_hazards_cleaned(self):
        def run(source):
            if source == "$\\alpha$":
                return "$alpha$"
            # t2l-shaped output carrying all three hazards.
            return "$5 0 % of #text[rate $\\alpha$] = 0 . 1 5$"

        out, warnings = typst_math.convert_markdown("$x$", run)
        self.assertEqual(warnings, [])
        self.assertEqual(out, '$50 #sym.percent of "rate " alpha = 0.15$')


@unittest.skipUnless(shutil.which("t2l"), "t2l not on PATH")
class RealT2lTest(unittest.TestCase):
    """The constructs the removed KaTeX-compat template sentence steered
    agents away from must now convert correctly deterministically."""

    def convert(self, markdown):
        out, warnings = typst_math.convert_markdown(markdown)
        self.assertEqual([w.as_dict() for w in warnings], [])
        return out

    def test_escaped_underscore_in_text(self):
        self.assertEqual(
            self.convert("$\\text{prop\\_var}$"), "$#text[prop\\_var]$"
        )

    def test_thin_space(self):
        self.assertEqual(self.convert("$a\\,b$"), "$a thin b$")

    def test_thin_space_in_paired_subscript(self):
        out = self.convert("$\\chi^2_{\\,p_1-p_0}$")
        self.assertNotIn("\\", out)
        self.assertIn("chi^(2)", out)
        self.assertIn("thin", out)

    def test_percent(self):
        self.assertEqual(self.convert("$50\\%$"), "$50 #sym.percent$")

    def test_nested_dollar_in_text(self):
        self.assertEqual(
            self.convert("$\\text{rate is $x$ high}$"), '$"rate is " x " high"$'
        )

    def test_digit_literals(self):
        self.assertEqual(
            self.convert("$P(\\text{yes}) = 0.15$"), "$P(#text[yes]) = 0.15$"
        )

    def test_display_fraction(self):
        out = self.convert(
            "$$\\sigma_{\\text{drug}}^{\\text{std}} = "
            "\\frac{0.15871}{1.503869} = 0.10553$$"
        )
        self.assertEqual(
            out,
            "$$sigma_(#text[drug])^(#text[std]) = "
            "frac(0.15871, 1.503869) = 0.10553$$",
        )


if __name__ == "__main__":
    unittest.main()
