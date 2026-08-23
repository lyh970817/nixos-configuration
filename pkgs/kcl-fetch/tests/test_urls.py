"""URL construction, with the DOIs that actually break naive encoding."""

from __future__ import annotations

import unittest
import urllib.parse

from kcl_fetch_lib import urls

#: The classic Wiley SICI DOI. Contains `<`, `>`, `;`, `(`, `)` and `:`.
SICI = "10.1002/(SICI)1097-0258(19970228)16:4<545::AID-SIM380>3.0.CO;2-Y"


class TestDoiNormalisation(unittest.TestCase):
    def test_resolver_prefixes_are_stripped(self):
        for decorated in (
            "https://doi.org/10.1000/abc",
            "http://dx.doi.org/10.1000/abc",
            "doi:10.1000/abc",
            "  10.1000/abc  ",
        ):
            self.assertEqual(urls.normalise_doi(decorated), "10.1000/abc")

    def test_is_doi(self):
        self.assertTrue(urls.is_doi("https://doi.org/10.1000/abc"))
        self.assertFalse(urls.is_doi("arXiv:2401.00001"))
        self.assertFalse(urls.is_doi("Some Paper Title"))


class TestDoiUrl(unittest.TestCase):
    def test_the_slash_between_prefix_and_suffix_stays_structural(self):
        self.assertEqual(urls.doi_url("10.1000/abc"), "https://doi.org/10.1000/abc")

    def test_a_sici_doi_survives_intact(self):
        built = urls.doi_url(SICI)
        path = urllib.parse.urlsplit(built).path
        self.assertEqual(urllib.parse.unquote(path), "/" + SICI)

    def test_fragment_and_query_characters_are_encoded_not_kept_raw(self):
        # A raw `#` truncates the DOI at the fragment and a raw `?` at the
        # query -- both silently, both producing a resolver 404.
        built = urls.doi_url("10.1000/a#b?c")
        self.assertNotIn("#", built)
        self.assertNotIn("?", built)
        self.assertEqual(
            urllib.parse.unquote(urllib.parse.urlsplit(built).path), "/10.1000/a#b?c"
        )

    def test_spaces_do_not_leak_through(self):
        self.assertNotIn(" ", urls.doi_url("10.1000/a b"))


class TestAccessTemplates(unittest.TestCase):
    target = "https://www.sciencedirect.com/science/article/pii/S0140673623000010"

    def test_openathens_wraps_a_fully_encoded_target(self):
        built = urls.openathens_url(self.target)
        self.assertTrue(built.startswith(urls.OPENATHENS_REDIRECTOR + "?url="))
        self.assertEqual(self._url_param(built), self.target)

    def test_ezproxy_wraps_a_fully_encoded_target(self):
        built = urls.ezproxy_url(self.target)
        self.assertTrue(built.startswith(urls.EZPROXY_LOGIN + "?url="))
        self.assertEqual(self._url_param(built), self.target)

    def test_the_dead_legacy_proxy_host_is_nowhere_in_the_module(self):
        self.assertNotIn("libproxy.kcl.ac.uk", urls.ezproxy_url(self.target))
        self.assertNotIn("libproxy", urls.EZPROXY_LOGIN)

    def test_the_targets_own_slashes_and_colons_are_escaped_not_passed_through(self):
        # If `https://` survives unescaped inside the `url=` parameter, the
        # redirector reads the target as part of its own path.
        built = urls.openathens_url(self.target)
        self.assertNotIn("https://www.sciencedirect.com", built)
        self.assertIn("https%3A%2F%2Fwww.sciencedirect.com", built)

    def test_a_target_with_its_own_query_string_round_trips(self):
        target = "https://pub.example/article?id=7&format=pdf"
        for build in (urls.openathens_url, urls.ezproxy_url):
            self.assertEqual(self._url_param(build(target)), target)

    def test_a_sici_doi_url_round_trips_through_both_templates(self):
        target = urls.doi_url(SICI)
        for template in urls.TEMPLATES:
            with self.subTest(template=template):
                self.assertEqual(self._url_param(urls.build(template, target)), target)

    def test_an_unknown_template_is_an_error_not_a_silent_default(self):
        with self.assertRaises(ValueError):
            urls.build("shibboleth-magic", self.target)

    @staticmethod
    def _url_param(built: str) -> str:
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(built).query)
        return query["url"][0]


class TestHostOf(unittest.TestCase):
    def test_www_is_dropped_and_case_folded(self):
        self.assertEqual(urls.host_of("https://WWW.Nature.com/articles/x"), "nature.com")

    def test_a_non_url_yields_an_empty_host_rather_than_raising(self):
        self.assertEqual(urls.host_of("not a url"), "")


if __name__ == "__main__":
    unittest.main()
