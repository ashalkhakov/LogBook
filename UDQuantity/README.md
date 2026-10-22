# UDQuantity

`UDQuantityField` (underivable.org): an amount and its unit in one field,
a number and, beside it, a box the unit is typed or picked in: money and
its currency, a distance and its unit. Foundation and AppKit only, for
macOS and GNUstep; it lives in Logbook for now and is to move to a
repository of its own.

## Using it

Drop a custom view of class `UDQuantityField` into a XIB, give it an
identifier, and bind its `value` (an `NSDecimalNumber`) and its `unit` as
you would a control's. Its units come from an object of the XIB connected
to its `units` outlet:

- `UDCurrencies`, currencies by their ISO 4217 codes, each named in the
  user's language ("EUR — Euro") and with the decimals their locale gives
  it (2 for EUR, 0 for JPY); `codes` narrows the list, the platform's
  common ones by default. Logbook's `LBCurrencies` lists those its model
  allows.
- `UDKeyPathUnits`, any objects, each said by a key path (`codeKeyPath`,
  and `nameKeyPath` for the name listed and searched), set as user-defined
  runtime attributes; its objects an array controller's, connected to its
  `controller` outlet, or set in code (`objects`).
- Anything else conforming to `UDQuantityUnits`.

```objc
@interface Sizes : NSObject <UDQuantityUnits>
@end

@implementation Sizes
- (NSArray *)unitsForQuantityField:(UDQuantityField *)field { return @[ @"mm", @"in" ]; }
- (NSString *)quantityField:(UDQuantityField *)field codeOfUnit:(id)unit { return unit; }
@end
```

What is typed in the box narrows its list to the units whose code or
name has it, codes beginning with it first ("eur", "dollar", "gallon").
Leaving the box takes the unit whose code was typed, or the one unit left;
anything else goes back to the unit before. A unit's decimals, when its
source says them, are always shown ("3.00 EUR"); otherwise the number has
up to the field's `decimals`.

- `showsValue` NO: the unit alone (a currency preferred).
- `unitWidth`: the box's width; `enabled`.
- Its number field and box are `valueField` and `unitBox`, named by its
  identifier with "Value" and "Unit" ("FillUpTotalValue",
  "FillUpTotalUnit") as it is shown, for tests and accessibility.
- `-reloadUnits` asks the source again; `-takeTypedUnit` takes what is
  typed, as leaving the box does.

A binding with `NSValidatesImmediately` is validated before it is set, an
error presented and the object's value shown again; a controller's no
selection, many values or not applicable shows nothing and is not to be
changed.
