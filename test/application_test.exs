defmodule ReflectOS.Core.ApplicationTest do
  use ExUnit.Case, async: true

  alias ReflectOS.Kernel.Section.Registry, as: SectionRegistry
  alias ReflectOS.Kernel.Layout.Registry, as: LayoutRegistry
  alias ReflectOS.Kernel.LayoutManager.Registry, as: LayoutManagerRegistry

  test "sections are all registered" do
    # Arrange
    {:ok, modules} = :application.get_key(:reflect_os_core, :modules)

    all =
      modules
      |> Enum.map(&Atom.to_string/1)
      |> Enum.filter(&Regex.match?(~r/ReflectOS\.Core\.Sections\.[^\.]*$/, &1))
      |> Enum.map(&String.to_existing_atom/1)

    # Act
    registered = SectionRegistry.list()

    # Assert
    assert [] == all -- registered
  end

  test "layouts are all registered" do
    # Arrange
    {:ok, modules} = :application.get_key(:reflect_os_core, :modules)

    all =
      modules
      |> Enum.map(&Atom.to_string/1)
      |> Enum.filter(&Regex.match?(~r/ReflectOS\.Core\.Layouts\.[^\.]*$/, &1))
      |> Enum.map(&String.to_existing_atom/1)

    # Act
    registered = LayoutRegistry.list()

    # Assert
    assert [] == all -- registered
  end

  test "layout managers are all registered" do
    # Arrange
    {:ok, modules} = :application.get_key(:reflect_os_core, :modules)

    all =
      modules
      |> Enum.map(&Atom.to_string/1)
      |> Enum.filter(&Regex.match?(~r/ReflectOS\.Core\.LayoutManagers\.[^\.]*$/, &1))
      |> Enum.map(&String.to_existing_atom/1)

    # Act
    registered = LayoutManagerRegistry.list()

    # Assert
    assert [] == all -- registered
  end
end
