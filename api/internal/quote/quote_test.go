package quote

import "testing"

func TestFind(t *testing.T) {
	src := Normalize("Vláda  „zradila“ národ –\n a to je fakt. 😀 Zradila!")
	cases := []struct {
		q    string
		want string
		ok   bool
	}{
		{"„zradila“ národ", "„zradila“ národ", true},
		{"\"zradila\" národ", "„zradila“ národ", true},
		{"národ - a to", "národ – a to", true},
		{"národ  –  a   to", "národ – a to", true},
		{"zradila národ", "", false}, // missing quote marks inside is a different text
		{"Vlada", "", false},         // diacritics must match
		{"", "", false},
		{"Zradila!", "Zradila!", true},
		{"\"fakt.\"", "fakt.", true}, // surrounding quote marks are stripped
	}
	for _, c := range cases {
		sp, ok := Find(src, c.q, 0)
		if ok != c.ok || (ok && sp.Quote != c.want) {
			t.Errorf("Find(%q) = %q,%v want %q,%v", c.q, sp.Quote, ok, c.want, c.ok)
		}
		if ok && src[sp.Start:sp.End] != sp.Quote {
			t.Errorf("byte span mismatch for %q", c.q)
		}
	}
}

func TestUTF16Offsets(t *testing.T) {
	src := "😀 ahoj světe"
	sp, ok := Find(src, "světe", 0)
	if !ok {
		t.Fatal("not found")
	}
	// emoji = 2 UTF-16 units, space 1, "ahoj " 5 → 8
	if sp.Start16 != 8 || sp.End16 != 13 {
		t.Fatalf("utf16 %d..%d", sp.Start16, sp.End16)
	}
}

func TestHint(t *testing.T) {
	src := "lež a lež"
	sp, _ := Find(src, "lež", 1)
	if sp.Start != len("lež a ") {
		t.Fatalf("hint ignored: %d", sp.Start)
	}
}

func TestNormalize(t *testing.T) {
	if got := Normalize("  a \n b  "); got != "a b" {
		t.Fatalf("%q", got)
	}
}
