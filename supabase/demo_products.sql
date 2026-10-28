-- Optional starter catalog for a new DataBee Supabase project.
-- Run in Supabase Dashboard > SQL Editor after schema.sql.
-- Inserts only missing demo products; existing products are left unchanged.

insert into public.products (
  id,
  name,
  brand,
  category,
  price,
  description,
  stock,
  image_url,
  specs,
  featured,
  is_active
)
values
  (
    'demo-gpu',
    'GeForce RTX 4080 SUPER 16GB',
    'NVIDIA',
    'GPUs',
    59999,
    'High-performance graphics for demanding games, creative work, and AI workloads.',
    8,
    '',
    '{"Memory":"16GB GDDR6X","Interface":"PCIe 4.0","TDP":"320W"}'::jsonb,
    true,
    true
  ),
  (
    'demo-cpu',
    'Ryzen 7 7800X3D',
    'AMD',
    'CPUs',
    21995,
    'An efficient 8-core desktop processor with 3D V-Cache for fast gaming.',
    12,
    '',
    '{"Cores":"8","Socket":"AM5","TDP":"120W"}'::jsonb,
    false,
    true
  ),
  (
    'demo-motherboard',
    'B650 AORUS Elite AX',
    'Gigabyte',
    'Motherboards',
    12950,
    'AM5 ATX motherboard with Wi-Fi, PCIe 4.0 storage, and DDR5 support.',
    6,
    '',
    '{"Socket":"AM5","Form factor":"ATX","Memory":"DDR5"}'::jsonb,
    false,
    true
  ),
  (
    'demo-memory',
    'Vengeance 32GB DDR5 6000',
    'Corsair',
    'Memory',
    5395,
    'A low-latency 32GB DDR5 memory kit for modern desktop PCs.',
    20,
    '',
    '{"Capacity":"32GB","Speed":"6000 MT/s","Type":"DDR5"}'::jsonb,
    false,
    true
  ),
  (
    'demo-storage',
    '990 PRO 2TB NVMe SSD',
    'Samsung',
    'Storage',
    8990,
    'Fast PCIe 4.0 NVMe storage with a 2TB capacity for games and projects.',
    14,
    '',
    '{"Capacity":"2TB","Interface":"PCIe 4.0 x4","Form":"M.2"}'::jsonb,
    false,
    true
  ),
  (
    'demo-psu',
    'RM850e 850W 80+ Gold',
    'Corsair',
    'Power Supplies',
    7190,
    'Fully modular 850W power supply, ready for current-generation builds.',
    9,
    '',
    '{"Power":"850W","Efficiency":"80+ Gold","Modular":"Yes"}'::jsonb,
    false,
    true
  )
on conflict (id) do nothing;
