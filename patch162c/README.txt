Patch162c
- Repairs only the Patch162 dynamic statement formula helper in export-shipment-excel/index.ts.
- Replaces fragile regex literals with RegExp constructors.
- Keeps N2 -> Row data -> Remark/Inland/Delivery Type formula automation.
- Does not touch Flutter UI, freight calculation, DB schema, or other exporter logic.
