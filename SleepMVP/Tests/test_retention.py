import unittest
from datetime import datetime, timedelta, timezone

from Beta.retention import aggregate


class RetentionTests(unittest.TestCase):
    def test_mature_cohort_deduplicates_and_preserves_unknowns(self):
        first = datetime(2026, 11, 1, tzinfo=timezone.utc)
        rows = [
            ("a", first, first + timedelta(days=7), first + timedelta(days=8)),
            ("a", first, None, first + timedelta(days=7)),
            ("b", first, first + timedelta(days=8), first + timedelta(days=9)),
            ("c", first, None, first + timedelta(days=2)),
            ("d", first + timedelta(days=6), None, first + timedelta(days=8)),
        ]
        self.assertEqual(aggregate(rows, first + timedelta(days=10)), (3, 2, 1))

    def test_early_report_can_confirm_reuse(self):
        first = datetime(2026, 11, 1, tzinfo=timezone.utc)
        second = first + timedelta(days=1)
        self.assertEqual(aggregate([("a", first, second, second)],
                                   first + timedelta(days=7)), (1, 1, 1))


if __name__ == "__main__":
    unittest.main()
